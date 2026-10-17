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

  describe "R12: the text version must be the current consent text version" do
    it "R12: the API's current version is the one the web consent form shows" do
      web_form = Rails.root.join("../web/src/identity/ConsentForm.tsx").read
      shown = web_form[/CONSENT_TEXT_VERSION\s*=\s*['"]([^'"]+)['"]/, 1]

      expect(Consent::CURRENT_TEXT_VERSION).to eq(shown)
    end

    it "R12: accepts the current version" do
      post "/consents", params: { text_version: Consent::CURRENT_TEXT_VERSION }, headers: auth_headers(user_id), as: :json

      expect(response).to have_http_status(:created)
      expect(Consent.where(user_id: user_id).pluck(:text_version)).to eq([ Consent::CURRENT_TEXT_VERSION ])
    end

    [ "1999-01-01", "not-a-version" ].each do |version|
      it "R12: rejects the unknown version #{version.inspect} with a 422 and stores no consent" do
        post "/consents", params: { text_version: version }, headers: auth_headers(user_id), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
        expect(response.parsed_body.dig("error", "message")).to be_present
        expect(Consent.where(user_id: user_id)).to be_empty
        expect(Consent::Ledger.active?(user_id)).to be(false)
      end
    end

    it "R12: rejects a missing version with a 4xx and stores no consent" do
      post "/consents", params: { other: "x" }, headers: auth_headers(user_id), as: :json

      expect(response.status).to be_in([ 400, 422 ])
      expect(Consent.where(user_id: user_id)).to be_empty
    end
  end
end
