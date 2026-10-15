require "rails_helper"

# R19: slot management is an admin endpoint. It rejects non-admins and audits every admin access.
RSpec.describe "Admin slot management", type: :request do
  let(:admin_id) { SecureRandom.uuid }
  let(:admin_headers) { auth_headers(admin_id, admin: true) }
  let(:slot_params) { { starts_at: "2030-03-04T09:00:00Z", ends_at: "2030-03-04T09:30:00Z" } }

  describe "POST /admin/slots" do
    it "lets an admin create a slot and returns it in ISO-8601 UTC (R37)" do
      post "/admin/slots", params: slot_params, headers: admin_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["slot"]).to include(
        "id" => be_present, "starts_at" => "2030-03-04T09:00:00Z", "ends_at" => "2030-03-04T09:30:00Z"
      )
      expect(Slot.count).to eq(1)
    end

    it "R37: stores a time sent with another zone's offset as the same UTC instant" do
      post "/admin/slots", params: { starts_at: "2030-03-04T01:00:00-08:00", ends_at: "2030-03-04T01:30:00-08:00" },
        headers: admin_headers, as: :json

      expect(Slot.last.starts_at).to eq(Time.utc(2030, 3, 4, 9, 0))
      expect(response.parsed_body.dig("slot", "starts_at")).to eq("2030-03-04T09:00:00Z")
    end

    it "R19: rejects a non-admin with a 403 envelope and creates nothing" do
      post "/admin/slots", params: slot_params, headers: auth_headers(SecureRandom.uuid), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("forbidden")
      expect(Slot.count).to eq(0)
    end

    it "R19: rejects a request with no token with a 401" do
      post "/admin/slots", params: slot_params, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Slot.count).to eq(0)
    end

    it "R19: writes an audit entry for the admin access, identified by an HMAC of the admin's ID" do
      expect {
        post "/admin/slots", params: slot_params, headers: admin_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
      expect(AuditEvent.last.actor_ref).to eq(OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("AUDIT_HMAC_KEY"), admin_id))
    end

    it "rejects a slot that ends before it starts with a 422 envelope" do
      post "/admin/slots", params: { starts_at: "2030-03-04T09:30:00Z", ends_at: "2030-03-04T09:00:00Z" },
        headers: admin_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
    end
  end

  describe "DELETE /admin/slots/:id" do
    let!(:slot) { create_slot }

    it "lets an admin remove an open slot" do
      delete "/admin/slots/#{slot.id}", headers: admin_headers

      expect(response.status).to be_between(200, 299)
      expect(Slot.exists?(slot.id)).to be(false)
    end

    it "R19: rejects a non-admin with a 403 and keeps the slot" do
      delete "/admin/slots/#{slot.id}", headers: auth_headers(SecureRandom.uuid)

      expect(response).to have_http_status(:forbidden)
      expect(Slot.exists?(slot.id)).to be(true)
    end

    it "R19: writes an audit entry for the admin access" do
      expect { delete "/admin/slots/#{slot.id}", headers: admin_headers }.to change(AuditEvent, :count).by(1)
    end
  end
end
