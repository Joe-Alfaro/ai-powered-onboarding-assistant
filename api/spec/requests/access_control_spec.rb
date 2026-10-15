require "rails_helper"

# Controllers mounted only for this spec. They contain no auth code of their own, so what they
# show is what every ApplicationController subclass gets.
module AccessControlSpec
  class WhoamiController < ApplicationController
    def show
      render json: { user_id: current_user_id }
    end
  end

  class OwnedRecord < ApplicationRecord
    self.table_name = "spec_owned_records"
  end

  # The scoped lookup every user-data endpoint follows: by ID, inside the caller's own records.
  class OwnedRecordsController < ApplicationController
    def show
      record = OwnedRecord.where(user_id: current_user_id).find(params[:id])
      render json: { id: record.id }
    end
  end

  class AdminController < ApplicationController
    before_action :require_admin!

    def show
      render json: { ok: true }
    end
  end
end

RSpec.describe "Access control", type: :request do
  let(:user_id) { SecureRandom.uuid }

  before do
    draw_spec_routes do
      get "/spec/whoami", to: "access_control_spec/whoami#show"
      get "/spec/owned_records/:id", to: "access_control_spec/owned_records#show"
      get "/spec/admin", to: "access_control_spec/admin#show"
    end
  end

  describe "R19: the API identifies the user from the verified token, never from the request" do
    it "uses the token's sub as the current user" do
      get "/spec/whoami", headers: auth_headers(user_id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["user_id"]).to eq(user_id)
    end

    it "ignores a user_id param and an X-User-Id header naming another user" do
      other_id = SecureRandom.uuid

      get "/spec/whoami", params: { user_id: other_id }, headers: auth_headers(user_id).merge("X-User-Id" => other_id)

      expect(response.parsed_body["user_id"]).to eq(user_id)
    end

    it "requires a token on every endpoint by default (401 envelope)" do
      get "/spec/whoami"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
    end

    it "rejects an invalid token with a 401 envelope" do
      get "/spec/whoami", headers: { "Authorization" => "Bearer #{supabase_token(sub: user_id, key: SupabaseTokens::ROGUE_EC_KEY, kid: 'rogue')}" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
    end

    it "rejects an expired token with a 401 envelope" do
      get "/spec/whoami", headers: auth_headers(user_id, claims: { exp: 1.minute.ago.to_i })

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a non-bearer Authorization header" do
      get "/spec/whoami", headers: { "Authorization" => "Basic #{Base64.strict_encode64('a:b')}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "R19: as user A, requesting user B's record by ID returns 403 or 404" do
    before do
      ActiveRecord::Base.connection.create_table(:spec_owned_records) { |t| t.uuid :user_id, null: false }
    end

    it_behaves_like "an owner-scoped resource" do
      let(:owner_id) { SecureRandom.uuid }
      let(:path) { "/spec/owned_records/#{AccessControlSpec::OwnedRecord.create!(user_id: owner_id).id}" }
    end
  end

  describe "R19: admin endpoints reject non-admins and audit every admin access" do
    let(:expected_actor_ref) { OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("AUDIT_HMAC_KEY"), user_id) }

    it "rejects a non-admin with a 403 envelope" do
      get "/spec/admin", headers: auth_headers(user_id)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
    end

    it "rejects a user who set role admin in their own user_metadata" do
      get "/spec/admin", headers: auth_headers(user_id, claims: { user_metadata: { role: "admin" } })

      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a request with no token with a 401" do
      get "/spec/admin"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lets an admin (app_metadata.role) through" do
      get "/spec/admin", headers: auth_headers(user_id, admin: true)

      expect(response).to have_http_status(:ok)
    end

    it "writes one audit entry per admin access" do
      expect {
        2.times { get "/spec/admin", headers: auth_headers(user_id, admin: true) }
      }.to change(AuditEvent, :count).by(2)
    end

    it "identifies the admin in the audit entry by an HMAC of their user ID" do
      get "/spec/admin", headers: auth_headers(user_id, admin: true)

      event = AuditEvent.last
      expect(event.actor_ref).to eq(expected_actor_ref)
      expect(event.action).to be_present
    end

    it "keeps the raw user ID out of the audit entry" do
      get "/spec/admin", headers: auth_headers(user_id, admin: true)

      expect(AuditEvent.column_names).not_to include("user_id")
      expect(AuditEvent.last.attributes.values.map(&:to_s)).to all(satisfy { |value| !value.include?(user_id) })
    end
  end
end
