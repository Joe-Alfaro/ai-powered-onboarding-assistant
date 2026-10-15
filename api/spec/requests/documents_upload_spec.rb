require "rails_helper"

# POST /documents: consent gate, upload validation, private storage and the OCR draft. OCR is
# stubbed here (see documents_tesseract_spec.rb for the real engine) and Storage is faked at the
# HTTP boundary.
RSpec.describe "POST /documents", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let(:jpeg) { upload_file(document_fixture("id.jpg")) }

  def expect_nothing_stored_or_processed(extractor)
    expect(storage.requests).to be_empty
    expect(storage.keys).to be_empty
    expect(extractor.called?).to be(false)
    expect(DocumentUpload.count).to eq(0)
    expect(identity_values(user_id)).to be_empty
  end

  describe "R12: the upload endpoint, called with a valid token but no consent, returns 403 and stores and processes nothing" do
    it "returns a 403 consent_required envelope when the user never consented" do
      extractor = stub_extractor

      post_document(user_id, jpeg)

      expect(response).to have_http_status(:forbidden)
      expect(error_body["code"]).to eq("consent_required")
      expect(error_body["message"]).to be_present
      expect_nothing_stored_or_processed(extractor)
    end

    it "returns 403 when the user's consent was revoked" do
      grant_consent(user_id)
      Consent::Ledger.revoke!(user_id: user_id)
      extractor = stub_extractor

      post_document(user_id, jpeg)

      expect(response).to have_http_status(:forbidden)
      expect(error_body["code"]).to eq("consent_required")
      expect_nothing_stored_or_processed(extractor)
    end

    it "checks the token's user: another user's consent doesn't count" do
      grant_consent(SecureRandom.uuid)
      extractor = stub_extractor

      post_document(user_id, jpeg)

      expect(response).to have_http_status(:forbidden)
      expect_nothing_stored_or_processed(extractor)
    end

    it "requires a signed-in user" do
      extractor = stub_extractor

      post "/documents", params: { file: jpeg }

      expect(response).to have_http_status(:unauthorized)
      expect_nothing_stored_or_processed(extractor)
    end
  end

  context "with consent" do
    before { grant_consent(user_id) }

    describe "an accepted upload" do
      it "returns the extracted fields as a draft, each with its value, confidence and level" do
        stub_extractor

        post_document(user_id, jpeg)

        expect(response).to have_http_status(:ok)
        expect(document_body["id"]).to be_present
        expect(document_body["status"]).to eq("pending")
        expect(document_body["manual_entry"]).to be(false)
        fields = document_body["fields"]
        expect(fields.keys).to contain_exactly("full_name", "date_of_birth", "address")
        expect(fields["full_name"]).to include("value" => "Jane Q Sample", "level" => "high")
        expect(fields["full_name"]["confidence"]).to be_between(0, 100)
        expect(fields["date_of_birth"]).to include("value" => "1985-03-14", "level" => "high")
        expect(fields["address"]).to include("value" => "123 Fake St, Springfield, ZZ 00000")
      end

      it "R5 [gotcha]: after upload and before confirmation, the onboarding record has no identity values, only the upload's draft" do
        stub_extractor

        post_document(user_id, jpeg)

        expect(identity_values(user_id)).to be_empty
        upload = DocumentUpload.find(document_body["id"])
        draft = upload.draft_fields.to_h.deep_stringify_keys
        expect(draft.dig("full_name", "value")).to eq("Jane Q Sample")
        expect(draft.dig("date_of_birth", "value")).to eq("1985-03-14")
      end

      it "R17: stores the image only in the private bucket, with the server's service key" do
        stub_extractor

        post_document(user_id, jpeg)

        expect(storage.keys.size).to eq(1)
        expect(storage.uploads.size).to eq(1)
        expect(storage.objects.values.first.body).to eq(File.binread(document_fixture("id.jpg")))
        expect(DocumentUpload.find(document_body["id"]).storage_key).to eq(storage.keys.first)
        expect(storage.requests.map(&:path)).to all(start_with("/object/#{storage.bucket}/"))
      end

      it "R17: returns no public or storage URL for the image" do
        stub_extractor

        post_document(user_id, jpeg)

        expect(response.body).not_to include("/object/")
        expect(response.body).not_to include(FakeSupabaseStorage::BASE_URL)
      end

      it "R17: stores only the three identity fields the flow needs, nothing else OCR read" do
        stub_extractor # its extraction also holds an ID number, D1234567

        post_document(user_id, jpeg)

        upload = DocumentUpload.find(document_body["id"])
        expect(upload.draft_fields.to_h.keys.map(&:to_s)).to all(be_in(%w[full_name date_of_birth address]))
        stored = [ upload.attributes, Onboarding.where(user_id: user_id).map(&:attributes) ].to_s
        expect(stored).not_to include("D1234567")
        expect(response.body).not_to include("D1234567")
      end

      it "R14/R15: discards the uploaded filename (not stored, not in the storage key, not logged, not returned)" do
        stub_extractor
        file = upload_file(document_fixture("id.jpg"), filename: "jane-q-sample-drivers-license.jpg")

        logs = capture_logs { post_document(user_id, file) }

        expect(response).to have_http_status(:ok)
        upload = DocumentUpload.find(document_body["id"])
        expect(upload.attributes.to_s).not_to include("jane-q-sample")
        expect(storage.requests.map(&:path).join).not_to include("jane-q-sample")
        expect(logs).not_to include("jane-q-sample")
        expect(response.body).not_to include("jane-q-sample")
      end

      it "hands the OCR engine a local copy of the uploaded image" do
        extractor = stub_extractor

        post_document(user_id, jpeg)

        expect(extractor.calls.size).to eq(1)
        expect(extractor.calls.first.head).to eq(File.binread(document_fixture("id.jpg"), 16))
      end

      it "R14: accepts a PNG" do
        stub_extractor

        post_document(user_id, upload_file(ocr_fixture("clean_id.png"), content_type: "image/png"))

        expect(response).to have_http_status(:ok)
      end
    end

    describe "R14: a renamed non-image, a truncated or corrupt image and an oversized file each get a clear 4xx, aren't processed and don't crash" do
      def expect_rejected(status:, code:)
        expect(response).to have_http_status(status)
        expect(error_body["code"]).to eq(code)
        expect(error_body["message"]).to be_present
        expect(error_body["actions"]).to include("manual_entry")
      end

      def expect_app_still_serves_uploads
        stub_extractor
        post_document(user_id, upload_file(document_fixture("id.jpg")))
        expect(response).to have_http_status(:ok)
      end

      it "rejects a PDF renamed to .jpg with an image content type, by its content (415 unsupported_file_type)" do
        extractor = stub_extractor

        post_document(user_id, upload_file(document_fixture("renamed_pdf.jpg"), content_type: "image/jpeg"))

        expect_rejected(status: :unsupported_media_type, code: "unsupported_file_type")
        expect_nothing_stored_or_processed(extractor)
        expect_app_still_serves_uploads
      end

      it "rejects a text file renamed to .png (415 unsupported_file_type)" do
        extractor = stub_extractor

        post_document(user_id, upload_bytes("just some text, not a picture\n" * 20, content_type: "image/png", filename: "id.png"))

        expect_rejected(status: :unsupported_media_type, code: "unsupported_file_type")
        expect_nothing_stored_or_processed(extractor)
      end

      it "accepts a real JPEG whose name and declared type are wrong, because the content decides" do
        stub_extractor

        post_document(user_id, upload_file(document_fixture("id.jpg"), content_type: "application/octet-stream", filename: "scan.txt"))

        expect(response).to have_http_status(:ok)
      end

      it "rejects a truncated JPEG (422 unreadable_image)" do
        extractor = stub_extractor

        post_document(user_id, upload_file(document_fixture("truncated.jpg")))

        expect_rejected(status: :unprocessable_content, code: "unreadable_image")
        expect_nothing_stored_or_processed(extractor)
        expect_app_still_serves_uploads
      end

      it "rejects a file with PNG magic bytes and a corrupt body (422 unreadable_image)" do
        extractor = stub_extractor

        post_document(user_id, upload_file(document_fixture("corrupt_body.png"), content_type: "image/png"))

        expect_rejected(status: :unprocessable_content, code: "unreadable_image")
        expect_nothing_stored_or_processed(extractor)
      end

      it "rejects an empty file (422 unreadable_image or 415 unsupported_file_type)" do
        extractor = stub_extractor

        post_document(user_id, upload_bytes(""))

        expect(response.status).to be_in([ 415, 422 ])
        expect(error_body["code"]).to be_in(%w[unreadable_image unsupported_file_type])
        expect_nothing_stored_or_processed(extractor)
      end

      it "rejects a file over MAX_UPLOAD_MB (413 file_too_large) and names the limit" do
        extractor = stub_extractor
        oversized = File.binread(document_fixture("id.jpg")) + ("\0".b * (10 * 1024 * 1024))

        post_document(user_id, upload_bytes(oversized))

        expect_rejected(status: :content_too_large, code: "file_too_large")
        expect(error_body["message"]).to include("10 MB")
        expect_nothing_stored_or_processed(extractor)
        expect_app_still_serves_uploads
      end

      it "returns 400 invalid_request when no file is attached" do
        extractor = stub_extractor

        post "/documents", params: {}, headers: auth_headers(user_id)

        expect(response).to have_http_status(:bad_request)
        expect(error_body["code"]).to eq("invalid_request")
        expect_nothing_stored_or_processed(extractor)
      end
    end

    describe "R14: HEIC phone photos are converted and processed" do
      it "converts a HEIC photo before OCR and storage, so both get a format they can read" do
        extractor = stub_extractor

        post_document(user_id, upload_file(document_fixture("id.heic"), content_type: "image/heic"))

        expect(response).to have_http_status(:ok)
        expect(document_body["manual_entry"]).to be(false)
        expect(extractor.calls.size).to eq(1)
        expect(image_format(extractor.calls.first.head)).to be_in(%i[jpeg png])
        expect(image_format(storage.objects.values.first.body)).to be_in(%i[jpeg png])
      end

      it "accepts HEIC by its content even when it is named .jpg" do
        stub_extractor

        post_document(user_id, upload_file(document_fixture("id.heic"), content_type: "image/jpeg", filename: "IMG_0001.jpg"))

        expect(response).to have_http_status(:ok)
      end

      def image_format(bytes)
        bytes = bytes.to_s.b
        return :jpeg if bytes.start_with?("\xFF\xD8\xFF".b)
        return :png if bytes.start_with?("\x89PNG\r\n\x1A\n".b)

        :other
      end
    end

    describe "R10: OCR failure, no text or low confidence offers manual entry and never returns a 500" do
      def expect_manual_entry(reason)
        expect(response).to have_http_status(:ok)
        expect(document_body["manual_entry"]).to be(true)
        expect(document_body["reason"]).to eq(reason)
        expect(document_body["fields"]).to eq("full_name" => nil, "date_of_birth" => nil, "address" => nil)
        expect(identity_values(user_id)).to be_empty
      end

      it "when OCR fails" do
        stub_extractor(Ocr::Extraction.failure("tesseract exited 1"))

        post_document(user_id, jpeg)

        expect_manual_entry("ocr_error")
      end

      it "when the OCR engine raises" do
        stub_extractor { raise "tesseract crashed" }

        post_document(user_id, jpeg)

        expect_manual_entry("ocr_error")
      end

      it "when OCR reads nothing" do
        stub_extractor(build_extraction)

        post_document(user_id, jpeg)

        expect_manual_entry("no_text")
      end

      it "when OCR's confidence is below OCR_CONFIDENCE_THRESHOLD" do
        stub_extractor(build_extraction(*lines_at(30, "NAME Jane Q Sample", "DOB 03/14/1985")))

        post_document(user_id, jpeg)

        expect_manual_entry("low_confidence")
      end

      it "when OCR reads text but no field" do
        stub_extractor(build_extraction(*lines_at(95, "SAMPLE IDENTIFICATION CARD", "SPECIMEN")))

        post_document(user_id, jpeg)

        expect_manual_entry("no_fields")
      end
    end

    describe "R11: partial extraction comes back without fabrication" do
      before do
        stub_extractor(build_extraction(
          [ [ "NAME", 95 ], [ "Jane", 96 ], [ "Q", 94 ], [ "Sample", 95 ] ],
          [ [ "ADDRESS", 95 ], [ "123", 40 ], [ "Fake", 45 ], [ "St", 42 ] ]
        ))
      end

      it "returns the fields it read with their confidence and nil for the field it didn't" do
        post_document(user_id, jpeg)

        expect(response).to have_http_status(:ok)
        expect(document_body["manual_entry"]).to be(false)
        fields = document_body["fields"]
        expect(fields["full_name"]).to include("value" => "Jane Q Sample", "level" => "high")
        expect(fields).to have_key("date_of_birth")
        expect(fields["date_of_birth"]).to be_nil
      end

      it "marks a low-confidence field differently from a high-confidence one" do
        post_document(user_id, jpeg)

        fields = document_body["fields"]
        expect(fields["address"]).to include("value" => "123 Fake St", "level" => "low")
        expect(fields["address"]["confidence"]).to be < fields["full_name"]["confidence"]
      end

      it "keeps the missing field nil in the stored draft too, never a guess" do
        post_document(user_id, jpeg)

        draft = DocumentUpload.find(document_body["id"]).draft_fields.to_h.deep_stringify_keys
        expect(draft["date_of_birth"]).to be_nil
        expect(identity_values(user_id)).to be_empty
      end
    end

    describe "R13 seam: the OCR write re-checks consent under a row lock" do
      it "writes no draft when consent is revoked while OCR is running, and keeps no image" do
        stub_extractor do
          Consent::Ledger.revoke!(user_id: user_id)
          clean_extraction
        end

        post_document(user_id, jpeg)

        expect(response).to have_http_status(:forbidden)
        expect(error_body["code"]).to eq("consent_required")
        expect(DocumentUpload.all.map(&:draft_fields).reject(&:blank?)).to be_empty
        expect(identity_values(user_id)).to be_empty
        expect(storage.keys).to be_empty
      end
    end
  end
end
