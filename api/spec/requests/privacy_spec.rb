require "rails_helper"

# DELETE /consents (withdraw consent) and DELETE /account (request deletion), each 204 with no body
# (R13, R19). The web contract is set in docs/decisions.md ("Web identity contracts set by the
# tests"). Storage is faked at the HTTP boundary, OCR is stubbed, the LLM is a FakeLlmAdapter
# behind Llm::Client.from_env, and the Supabase Auth admin API is stubbed. Consent::Ledger is real.
RSpec.describe "Consent withdrawal and account deletion", type: :request do
  include SchedulingHelpers

  let(:user_id) { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let(:llm) { FakeLlmAdapter.new.always_respond_with("intent" => "ask-question", "assessment_fields" => {}, "reply" => "Happy to help.") }

  before do
    stub_extractor
    stub_auth_admin
    allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: llm))
  end

  # Uploads the sample card through the API, as the user, and returns the document ID.
  def upload_as(owner_id)
    grant_consent(owner_id) unless Consent::Ledger.active?(owner_id)
    post_document(owner_id, upload_file(document_fixture("id.jpg")))
    expect(response).to have_http_status(:ok)
    document_body["id"]
  end

  def storage_key_for(document_id)
    DocumentUpload.find(document_id).storage_key
  end

  def chat_as(owner_id, text = "What happens next?")
    post "/chat/messages", params: { message: text }, headers: auth_headers(owner_id), as: :json
  end

  {
    "DELETE /consents" => { path: "/consents", action: "consent_withdrawn" },
    "DELETE /account" => { path: "/account", action: "account_deleted" }
  }.each do |name, endpoint|
    describe name do
      let(:path) { endpoint[:path] }

      def revoke(owner_id = user_id, params: {})
        delete path, params: params, headers: auth_headers(owner_id), as: :json
      end

      it "R13: the user can do it from the app: returns 204 with no body" do
        seed_personal_data(user_id, storage: storage)

        revoke

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      end

      it "R13: hard-deletes images, draft and confirmed identity fields, messages, transcripts and assessments" do
        seeded = seed_personal_data(user_id, storage: storage)

        revoke

        expect(remaining_rows(seeded)).to eq(nothing_left)
        expect(storage_deletes_for(storage, seeded.image_key)).not_to be_empty
        expect(storage.exists?(seeded.image_key)).to be(false)
      end

      it "R13: requests to retrieve the deleted document or its image return 404" do
        id = upload_as(user_id)

        revoke

        get "/documents/#{id}", headers: auth_headers(user_id)
        expect(response).to have_http_status(:not_found)
        expect(error_body).to include("code", "message")

        get "/documents/#{id}/preview", headers: auth_headers(user_id)
        expect(response).to have_http_status(:not_found)
        expect(storage.signed.size).to eq(0)
      end

      it "R13: a signed URL issued before the revocation no longer works (the object is deleted)" do
        id = upload_as(user_id)
        key = storage_key_for(id)
        get "/documents/#{id}/preview", headers: auth_headers(user_id)
        url = response.parsed_body.fetch("url")
        expect(fetch_signed_url(url)).to be_a(Net::HTTPOK)

        revoke

        expect(storage_deletes_for(storage, key)).not_to be_empty
        expect(storage.exists?(key)).to be(false)
        expect(fetch_signed_url(url)).not_to be_a(Net::HTTPSuccess)
      end

      it "R13: later chat messages, with a token that is still valid, make no LLM call and store nothing" do
        seed_personal_data(user_id, storage: storage)
        chat_as(user_id)
        expect(llm.call_count).to eq(1)

        revoke
        chat_as(user_id, "I'm still here, can you help?")

        expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
        expect(response.parsed_body.fetch("error")).to include("code", "message")
        expect(llm.call_count).to eq(1)
        expect(Message.joins(:conversation).where(conversations: { user_id: user_id })).to be_empty
      end

      it "R13: an OCR request in flight at revocation writes nothing afterwards" do
        grant_consent(user_id)
        stub_extractor do
          # The revocation arrives as a separate request while OCR is reading the image.
          revocation = ActionDispatch::Integration::Session.new(Rails.application)
          revocation.delete path, headers: auth_headers(user_id).merge("Content-Type" => "application/json")
          expect(revocation.response).to have_http_status(:no_content)
          clean_extraction
        end

        post_document(user_id, upload_file(document_fixture("id.jpg")))

        expect(response).to have_http_status(:forbidden)
        expect(DocumentUpload.joins(:onboarding).where(onboardings: { user_id: user_id })).to be_empty
        expect(DocumentUpload.all.map(&:draft_fields).compact_blank).to be_empty
        expect(identity_values(user_id)).to be_empty
        expect(storage.keys).to be_empty
      end

      it "R13: writes an audit entry with only an HMAC actor_ref, the action and a timestamp" do
        seed_personal_data(user_id, storage: storage)

        expect { revoke }.to change(AuditEvent, :count).by(1)

        event = AuditEvent.last
        expect(AuditEvent.column_names).to contain_exactly("id", "actor_ref", "action", "created_at")
        expect(event.actor_ref).to eq(OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("AUDIT_HMAC_KEY"), user_id))
        expect(event.action).to eq(endpoint[:action])
        expect(event.created_at).to be_within(1.minute).of(Time.current)
        personal = [ user_id, "#{user_id}@example.test", *DocumentHelpers::CLEAN_FIELDS.values ]
        expect(event.attributes.values.map(&:to_s)).to all(satisfy { |value| personal.none? { |p| value.include?(p) } })
      end

      it "R13: is safe to repeat (a retry after a lost response still gets 204)" do
        seed_personal_data(user_id, storage: storage)

        2.times { revoke }

        expect(response).to have_http_status(:no_content)
      end

      it "R19: requires a bearer token and deletes nothing without one" do
        seeded = seed_personal_data(user_id, storage: storage)

        delete path, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(remaining_rows(seeded)).to eq(everything_left(seeded))
        expect(AuditEvent.count).to eq(0)
        expect(any_auth_admin_delete).not_to have_been_made
      end

      it "R19: a user can only revoke and delete themselves; a user_id in the request is ignored" do
        mine = seed_personal_data(user_id, storage: storage)
        theirs = seed_personal_data(other_user_id, storage: storage)

        revoke(user_id, params: { user_id: other_user_id, id: other_user_id })

        expect(response).to have_http_status(:no_content)
        expect(remaining_rows(mine)).to eq(nothing_left)
        expect(remaining_rows(theirs)).to eq(everything_left(theirs))
        expect(storage.exists?(theirs.image_key)).to be(true)
        expect(Consent::Ledger.active?(other_user_id)).to be(true)
        expect(auth_admin_delete_for(other_user_id)).not_to have_been_made
        expect(AuditEvent.pluck(:actor_ref)).to eq([ AuditEvent.actor_ref_for(user_id) ])
      end

      it "R19: there is no route to revoke or delete another user by ID" do
        delete "#{path}/#{other_user_id}", headers: auth_headers(user_id), as: :json

        expect(response).to have_http_status(:not_found)
        expect(any_auth_admin_delete).not_to have_been_made
      end
    end
  end

  describe "DELETE /consents specifics" do
    it "R13: keeps the Auth user, so the person can still sign in and continue by hand" do
      seed_personal_data(user_id, storage: storage)

      delete "/consents", headers: auth_headers(user_id), as: :json

      expect(response).to have_http_status(:no_content)
      expect(any_auth_admin_delete).not_to have_been_made
    end

    it "R13: chat answers 403 consent_withdrawn" do
      seed_personal_data(user_id, storage: storage)
      delete "/consents", headers: auth_headers(user_id), as: :json

      chat_as(user_id)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("consent_withdrawn")
      expect(llm.call_count).to eq(0)
    end
  end

  describe "DELETE /account specifics" do
    it "R13: deletes the Supabase Auth user through the admin API" do
      seed_personal_data(user_id, storage: storage)

      delete "/account", headers: auth_headers(user_id), as: :json

      expect(auth_admin_delete_for(user_id)).to have_been_made.once
    end

    it "R13 decision: cancels an active booking and frees the slot for someone else" do
      slot = create_slot
      create_booking(user_id: user_id, slot: slot)

      delete "/account", headers: auth_headers(user_id), as: :json

      expect(active_bookings_on(slot)).to be_empty
      get "/slots", headers: auth_headers(other_user_id)
      expect(response.parsed_body.to_json).to include(slot.id)
      post "/bookings", params: { slot_id: slot.id }, headers: auth_headers(other_user_id), as: :json
      expect(response).to have_http_status(:created)
    end

    it "R13: the deleted user's booking can't be retrieved afterwards" do
      booking = create_booking(user_id: user_id)

      delete "/account", headers: auth_headers(user_id), as: :json

      get "/bookings/#{booking.id}", headers: auth_headers(user_id)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "R13: an OCR request in flight on another thread at revocation writes nothing afterwards (real Postgres, real threads)" do
    self.use_transactional_tests = false

    after do
      [ Message, Conversation, Assessment, DocumentUpload, Onboarding, Consent, Booking, Slot, AuditEvent ].each(&:delete_all)
    end

    it "R13: the upload's draft write re-checks consent under the lock and finds it gone" do
      grant_consent(user_id)
      in_ocr = Queue.new
      resume = Queue.new
      stub_extractor do
        in_ocr << true
        resume.pop
        clean_extraction
      end
      headers = auth_headers(user_id)

      upload_status = with_connection_pool_of(5) do
        uploader = Thread.new do
          Rails.application.executor.wrap do
            session = ActionDispatch::Integration::Session.new(Rails.application)
            session.post "/documents", params: { file: upload_file(document_fixture("id.jpg")) }, headers: headers
            session.response.status
          end
        end
        in_ocr.pop
        revocation = ActionDispatch::Integration::Session.new(Rails.application)
        revocation.delete "/consents", headers: headers.merge("Content-Type" => "application/json")
        expect(revocation.response).to have_http_status(:no_content)
        resume << true
        uploader.value
      end

      expect(upload_status).to eq(403)
      expect(DocumentUpload.count).to eq(0)
      expect(identity_values(user_id)).to be_empty
      expect(storage.keys).to be_empty
    end
  end
end
