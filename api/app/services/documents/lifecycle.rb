module Documents
  # An ID image from upload to confirmation (R5, R10, R11, R12, R13, R17). The image goes to the
  # private bucket and OCR's three fields go to document_uploads.draft_fields; nothing reaches the
  # onboarding record until the user confirms. Confirming saves the values as sent, clears the
  # draft and deletes the image. Unconfirmed uploads are purged by PurgeExpiredUploadsJob.
  class Lifecycle
    PREVIEW_SECONDS = 60

    def initialize(user_id:, storage: Storage::Client.default)
      @user_id = user_id
      @storage = storage
    end

    # Validates, stores and reads the image, and returns the pending DocumentUpload. Consent is
    # checked before anything is stored or read, and again under a row lock before the draft is
    # written, so a revocation during OCR leaves no draft and no image.
    def upload(file)
      require_consent!
      Uploads::Validator.new.call(file) do |image|
        # The row comes first, so an image whose upload fails halfway is still found by the purge.
        id = SecureRandom.uuid
        upload = DocumentUpload.create!(id: id, onboarding: Onboarding.for_user(@user_id),
                                        storage_key: "#{@user_id}/#{id}.#{image.extension}", expires_at: DocumentUpload::TTL.from_now)
        begin
          File.open(image.path, "rb") { |io| @storage.upload(upload.storage_key, io, content_type: image.content_type) }
          result = read(image.path)
          Consent::Ledger.with_active_consent(@user_id) do
            upload.update!(draft_fields: draft_fields(result), ocr_reason: result.reason&.to_s)
          end
          upload
        rescue StandardError
          discard_later_if_unreachable(upload)
          raise
        end
      end
    rescue Consent::Ledger::NotGiven
      raise consent_required
    end

    def find(id)
      DocumentUpload.pending_for(@user_id).find(id)
    end

    def preview_url(id)
      @storage.signed_url(find(id).storage_key, expires_in: PREVIEW_SECONDS)
    end

    # Saves the user's values for the three fields as sent, marked as from OCR, then clears the
    # draft and deletes the image. Raises ActiveRecord::RecordInvalid, changing nothing, when a
    # value is blank or not a real date.
    def confirm(id, fields)
      DocumentUpload.transaction do
        upload = find(id).lock!
        raise ActiveRecord::RecordNotFound unless upload.status == "pending"

        upload.onboarding.confirm_identity!(fields, source: "ocr")
        upload.update!(status: "confirmed", draft_fields: nil)
        # Inside the transaction: if Storage can't delete the image, the confirmation rolls back
        # and the user can retry, rather than the image outliving the confirmation.
        @storage.delete(upload.storage_key)
        upload.onboarding
      end
    end

    # Saves typed-in identity with no image (R10), and drops any pending upload the user gave up on.
    def enter_manually(fields)
      onboarding = Onboarding.for_user(@user_id)
      onboarding.confirm_identity!(fields, source: "manual")
      DocumentUpload.pending_for(@user_id).find_each { |upload| discard(upload) }
      onboarding
    end

    # Deletes the image and the row. An image already gone from Storage counts as deleted.
    def discard(upload)
      @storage.delete(upload.storage_key)
      upload.destroy!
    end

    private

    def discard_later_if_unreachable(upload)
      discard(upload)
    rescue Storage::Client::Error
      nil # The row stays, so the purge job deletes the image once Storage is back.
    end

    def require_consent!
      raise consent_required unless Consent::Ledger.active?(@user_id)
    end

    def consent_required
      ApiError.new(status: 403, code: "consent_required",
                   message: "Please agree to the ID photo consent before uploading, or enter your details by hand.",
                   actions: [ "manual_entry" ])
    end

    # The engine is built per upload. It never raises by contract, but a crash still becomes
    # manual entry rather than a 500 (R10).
    def read(path)
      extraction = begin
        Ocr::Extractor.new.call(path)
      rescue StandardError => error
        Ocr::Extraction.failure(error.class.name)
      end
      Ocr::FieldMapper.new.call(extraction)
    end

    # Only the three identity fields, each nil or its value, confidence and level (R11, R17).
    def draft_fields(result)
      result.fields.slice(*Ocr::FieldMapper::FIELDS).transform_values do |reading|
        reading && { "value" => reading.value, "confidence" => reading.confidence.round(1), "level" => reading.level.to_s }
      end.stringify_keys
    end
  end
end
