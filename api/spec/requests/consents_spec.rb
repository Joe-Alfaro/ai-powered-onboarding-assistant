require "rails_helper"

RSpec.describe "POST /consents", type: :request do
  let(:user_id) { SecureRandom.uuid }

  describe "R12: each consent is stored with the user, a timestamp and the consent text version" do
    it "stores the token's user, the time and the text version, and returns them" do
      freeze_time do
        post "/consents", params: { text_version: "2026-10-15" }, headers: auth_headers(user_id), as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["consent"]).to include("text_version" => "2026-10-15")
        expect(Time.zone.parse(response.parsed_body.dig("consent", "granted_at"))).to eq(Time.current)

        consent = Consent.find_by!(user_id: user_id)
        expect(consent.text_version).to eq("2026-10-15")
        expect(consent.granted_at).to eq(Time.current)
        expect(Consent::Ledger.active?(user_id)).to be(true)
      end
    end

    it "R19: records consent for the token's user, ignoring a user_id in the body" do
      other_id = SecureRandom.uuid

      post "/consents", params: { text_version: "2026-10-15", user_id: other_id }, headers: auth_headers(user_id), as: :json

      expect(response).to have_http_status(:created)
      expect(Consent.where(user_id: user_id).count).to eq(1)
      expect(Consent.where(user_id: other_id)).to be_empty
    end

    it "rejects a consent with no text version and stores nothing" do
      post "/consents", params: {}, headers: auth_headers(user_id), as: :json

      expect(response.status).to be_in([ 400, 422 ])
      expect(response.parsed_body.dig("error", "code")).to be_in(%w[invalid_request validation_failed])
      expect(Consent.where(user_id: user_id)).to be_empty
    end

    it "requires a signed-in user" do
      post "/consents", params: { text_version: "2026-10-15" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Consent.count).to eq(0)
    end
  end
end
