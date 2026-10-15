module Documents
  # Hard-deletes the image and the row of every upload left unconfirmed past DocumentUpload::TTL
  # (R17). Runs hourly from config/recurring.yml. An image already gone from Storage counts as
  # deleted; if Storage can't be reached the row stays and the next run tries again.
  class PurgeExpiredUploadsJob < ApplicationJob
    queue_as :default

    def perform
      DocumentUpload.expired.includes(:onboarding).find_each do |upload|
        Lifecycle.new(user_id: upload.onboarding.user_id).discard(upload)
      rescue Storage::Client::Error => error
        Rails.logger.warn({ event: "document_purge_failed", document_upload_id: upload.id, error_class: error.class.name }.to_json)
      end
    end
  end
end
