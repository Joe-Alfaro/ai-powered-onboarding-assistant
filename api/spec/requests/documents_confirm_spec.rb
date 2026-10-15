require "rails_helper"

# What happens to an uploaded document after OCR: reading the draft, previewing the image through
# a signed URL, and confirming the fields. OCR is stubbed and Storage is faked at the HTTP boundary.
RSpec.describe "Document drafts, previews and confirmation", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let(:edited) { { full_name: "Janet Q Sample", date_of_birth: "1985-03-15", address: "125 Fake St, Springfield, ZZ 00001" } }

  before { stub_extractor }

  # Uploads the sample card as the user and returns the new document's ID.
  def upload_as(owner_id)
    grant_consent(owner_id) unless Consent::Ledger.active?(owner_id)
    post_document(owner_id, upload_file(document_fixture("id.jpg")))
    expect(response).to have_http_status(:ok)
    document_body["id"]
  end

  def confirm(id, fields, as: user_id)
    post "/documents/#{id}/confirm", params: fields, headers: auth_headers(as), as: :json
  end

  def storage_key_for(id)
    DocumentUpload.find(id).storage_key
  end

  def draft_for(id)
    DocumentUpload.where(id: id).pick(:draft_fields)
  end

  describe "GET /documents/:id" do
    it "returns the user's pending draft" do
      id = upload_as(user_id)

      get "/documents/#{id}", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(document_body["id"]).to eq(id)
      expect(document_body["status"]).to eq("pending")
      expect(document_body.dig("fields", "full_name", "value")).to eq("Jane Q Sample")
    end
  end

  describe "R17: previews only through short-lived signed URLs" do
    it "returns a signed URL that lives 60 seconds and no public URL" do
      id = upload_as(user_id)
      key = storage_key_for(id)

      get "/documents/#{id}/preview", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["expires_in"]).to eq(60)
      expect(storage.signed).to eq([ { key: key, expires_in: 60 } ])
      url = response.parsed_body["url"]
      expect(url).to start_with("#{FakeSupabaseStorage::BASE_URL}/object/sign/#{storage.bucket}/")
      expect(url).to include("token=")
      expect(url).not_to include("/object/public/")
    end

    it "signs a fresh URL on every request rather than handing out a stored one" do
      id = upload_as(user_id)

      2.times { get "/documents/#{id}/preview", headers: auth_headers(user_id) }

      expect(storage.signed.size).to eq(2)
    end
  end

  describe "R5: POST /documents/:id/confirm saves the values the user edited, as edited" do
    it "writes the edited values to the onboarding record and marks them as from OCR" do
      id = upload_as(user_id)

      freeze_time do
        confirm(id, edited)

        expect(response).to have_http_status(:ok)
        onboarding = Onboarding.find_by!(user_id: user_id)
        expect(onboarding.full_name).to eq("Janet Q Sample")
        expect(onboarding.date_of_birth.to_s).to eq("1985-03-15")
        expect(onboarding.address).to eq("125 Fake St, Springfield, ZZ 00001")
        expect(onboarding.identity_source).to eq("ocr")
        expect(onboarding.confirmed_at).to eq(Time.current)
      end
      expect(response.parsed_body.dig("onboarding", "full_name")).to eq("Janet Q Sample")
    end

    it "saves the OCR values unchanged when the user confirms without editing" do
      id = upload_as(user_id)

      confirm(id, DocumentHelpers::CLEAN_FIELDS)

      expect(identity_values(user_id).transform_values(&:to_s)).to eq(DocumentHelpers::CLEAN_FIELDS)
    end

    it "lets the user fill in a field OCR couldn't read" do
      stub_extractor(build_extraction(*lines_at(95, "NAME Jane Q Sample")))
      id = upload_as(user_id)

      confirm(id, DocumentHelpers::CLEAN_FIELDS)

      expect(response).to have_http_status(:ok)
      expect(Onboarding.find_by!(user_id: user_id).date_of_birth.to_s).to eq("1985-03-14")
    end

    it "R17: stores only the three identity fields, ignoring anything else sent" do
      id = upload_as(user_id)

      confirm(id, edited.merge(id_number: "D1234567", user_id: SecureRandom.uuid, identity_source: "manual"))

      expect(response).to have_http_status(:ok)
      onboarding = Onboarding.find_by!(user_id: user_id)
      expect(onboarding.identity_source).to eq("ocr")
      expect(onboarding.attributes.to_s).not_to include("D1234567")
    end

    it "rejects a blank or impossible field with 422 and saves nothing, keeping the draft and image" do
      id = upload_as(user_id)
      key = storage_key_for(id)

      confirm(id, edited.merge(full_name: " "))
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")

      confirm(id, edited.merge(date_of_birth: "1985-02-30"))
      expect(response).to have_http_status(:unprocessable_content)

      expect(identity_values(user_id)).to be_empty
      expect(draft_for(id)).to be_present
      expect(storage.exists?(key)).to be(true)
    end
  end

  describe "R5 [gotcha]: skipping confirmation saves nothing" do
    it "leaves the onboarding record without identity values after upload, reads and previews" do
      id = upload_as(user_id)
      get "/documents/#{id}", headers: auth_headers(user_id)
      get "/documents/#{id}/preview", headers: auth_headers(user_id)

      expect(identity_values(user_id)).to be_empty
      onboarding = Onboarding.find_by(user_id: user_id)
      expect(onboarding&.confirmed_at).to be_nil
      expect(onboarding&.identity_source).to be_nil
    end
  end

  describe "R17: after the user confirms, the source image is deleted and a check shows it gone" do
    it "deletes the image from storage on confirm" do
      id = upload_as(user_id)
      key = storage_key_for(id)
      expect(storage.exists?(key)).to be(true)

      confirm(id, edited)

      expect(response).to have_http_status(:ok)
      expect(storage.exists?(key)).to be(false)
      expect(storage.requests.map(&:method)).to include("DELETE")
    end

    it "clears the draft fields, so extracted values live only on the onboarding record" do
      id = upload_as(user_id)

      confirm(id, edited)

      expect(draft_for(id)).to be_blank
    end

    it "no longer serves the draft or a preview once confirmed (404)" do
      id = upload_as(user_id)
      confirm(id, edited)
      signs_before = storage.signed.size

      get "/documents/#{id}/preview", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
      expect(storage.signed.size).to eq(signs_before)

      confirm(id, edited)
      expect(response.status).to be_in([ 404, 409 ])
    end
  end

  describe "R19: user A can't read, preview or confirm user B's upload" do
    let(:owner_id) { SecureRandom.uuid }

    it "returns 404 for A reading B's draft" do
      id = upload_as(owner_id)
      grant_consent(user_id)

      get "/documents/#{id}", headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("Jane Q Sample")
    end

    it "returns 404 for A previewing B's image and signs nothing" do
      id = upload_as(owner_id)
      signs_before = storage.signed.size

      get "/documents/#{id}/preview", headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("/object/")
      expect(storage.signed.size).to eq(signs_before)
    end

    it "returns 404 for A confirming B's upload and changes nothing for either user" do
      id = upload_as(owner_id)
      key = storage_key_for(id)
      grant_consent(user_id)

      confirm(id, edited, as: user_id)

      expect(response).to have_http_status(:not_found)
      expect(identity_values(user_id)).to be_empty
      expect(identity_values(owner_id)).to be_empty
      expect(draft_for(id)).to be_present
      expect(storage.exists?(key)).to be(true)
    end

    it "ignores a user_id param naming the owner" do
      id = upload_as(owner_id)

      get "/documents/#{id}", params: { user_id: owner_id }, headers: auth_headers(user_id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
