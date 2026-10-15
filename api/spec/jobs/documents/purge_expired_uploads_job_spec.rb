require "rails_helper"

# R17 [gotcha]: images from abandoned, never-confirmed uploads are purged by a scheduled job after
# a documented time-to-live (1 hour). These specs upload through the API, never confirm, advance
# time and run the job.
RSpec.describe "Documents::PurgeExpiredUploadsJob", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }

  before do
    stub_extractor
    grant_consent(user_id)
  end

  def upload
    post_document(user_id, upload_file(document_fixture("id.jpg")))
    expect(response).to have_http_status(:ok)
    id = document_body["id"]
    [ id, DocumentUpload.find(id).storage_key ]
  end

  it "uploads, never confirms, advances past the 1 hour TTL, and finds the image and draft gone" do
    id, key = upload

    travel 61.minutes do
      Documents::PurgeExpiredUploadsJob.perform_now
    end

    expect(storage.exists?(key)).to be(false)
    expect(DocumentUpload.where(id: id)).not_to exist
    expect(identity_values(user_id)).to be_empty
    get "/documents/#{id}", headers: auth_headers(user_id)
    expect(response).to have_http_status(:not_found)
  end

  it "keeps an unconfirmed upload that is younger than 1 hour" do
    id, key = upload

    travel 59.minutes do
      Documents::PurgeExpiredUploadsJob.perform_now
    end

    expect(storage.exists?(key)).to be(true)
    expect(DocumentUpload.where(id: id)).to exist
  end

  it "purges only the expired uploads when old and new ones are mixed" do
    old_id, old_key = upload
    travel 45.minutes
    new_id, new_key = upload

    travel 20.minutes
    Documents::PurgeExpiredUploadsJob.perform_now

    expect(storage.exists?(old_key)).to be(false)
    expect(DocumentUpload.where(id: old_id)).not_to exist
    expect(storage.exists?(new_key)).to be(true)
    expect(DocumentUpload.where(id: new_id)).to exist
  end

  it "leaves the confirmed identity values alone" do
    id, = upload
    post "/documents/#{id}/confirm", params: DocumentHelpers::CLEAN_FIELDS, headers: auth_headers(user_id), as: :json
    expect(response).to have_http_status(:ok)

    travel 2.hours do
      Documents::PurgeExpiredUploadsJob.perform_now
    end

    expect(identity_values(user_id)[:full_name]).to eq("Jane Q Sample")
  end

  it "removes the database row even when the object is already gone from storage" do
    id, key = upload
    storage.objects.delete(key)

    travel 61.minutes do
      expect { Documents::PurgeExpiredUploadsJob.perform_now }.not_to raise_error
    end

    expect(DocumentUpload.where(id: id)).not_to exist
  end

  it "is scheduled as a Solid Queue recurring task in production" do
    recurring = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
    task = recurring.fetch("production").values.find { |entry| entry["class"] == "Documents::PurgeExpiredUploadsJob" }

    expect(task).not_to be_nil
    expect(task["schedule"]).to be_present
  end
end
