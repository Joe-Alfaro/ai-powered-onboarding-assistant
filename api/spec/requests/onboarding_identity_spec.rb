require "rails_helper"

# R10: a user can finish the identity step without uploading any image, by typing the fields in.
RSpec.describe "POST /onboarding/identity", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let(:fields) { { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" } }

  def submit(params, as: user_id)
    post "/onboarding/identity", params: params, headers: auth_headers(as), as: :json
  end

  it "R10: saves manually entered identity with no upload and no OCR" do
    extractor = stub_extractor

    freeze_time do
      submit(fields)

      expect(response).to have_http_status(:ok)
      onboarding = Onboarding.find_by!(user_id: user_id)
      expect(onboarding.full_name).to eq("Jane Q Sample")
      expect(onboarding.date_of_birth.to_s).to eq("1985-03-14")
      expect(onboarding.address).to eq("123 Fake St, Springfield, ZZ 00000")
      expect(onboarding.identity_source).to eq("manual")
      expect(onboarding.confirmed_at).to eq(Time.current)
    end
    expect(response.parsed_body.dig("onboarding", "identity_source")).to eq("manual")
    expect(extractor.called?).to be(false)
    expect(storage.requests).to be_empty
    expect(DocumentUpload.count).to eq(0)
  end

  it "R10: works after OCR offered manual entry for a failed upload" do
    grant_consent(user_id)
    stub_extractor(Ocr::Extraction.failure("tesseract exited 1"))
    post_document(user_id, upload_file(document_fixture("id.jpg")))
    expect(document_body["manual_entry"]).to be(true)

    submit(fields)

    expect(response).to have_http_status(:ok)
    expect(identity_values(user_id)[:full_name]).to eq("Jane Q Sample")
  end

  it "rejects a blank name, a missing address or an impossible date of birth with 422 and saves nothing" do
    [ fields.merge(full_name: ""), fields.except(:address), fields.merge(date_of_birth: "1985-02-30"),
      fields.merge(date_of_birth: 1.day.from_now.to_date.iso8601) ].each do |params|
      submit(params)

      expect(response).to have_http_status(:unprocessable_content), "expected 422 for #{params.inspect}"
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
    expect(identity_values(user_id)).to be_empty
  end

  it "R17: stores only the three identity fields, ignoring anything else sent" do
    submit(fields.merge(id_number: "D1234567", identity_source: "ocr"))

    onboarding = Onboarding.find_by!(user_id: user_id)
    expect(onboarding.identity_source).to eq("manual")
    expect(onboarding.attributes.to_s).not_to include("D1234567")
  end

  it "R19: saves for the token's user, ignoring a user_id param" do
    other_id = SecureRandom.uuid

    submit(fields.merge(user_id: other_id))

    expect(identity_values(user_id)[:full_name]).to eq("Jane Q Sample")
    expect(identity_values(other_id)).to be_empty
  end

  it "requires a signed-in user" do
    post "/onboarding/identity", params: fields, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
