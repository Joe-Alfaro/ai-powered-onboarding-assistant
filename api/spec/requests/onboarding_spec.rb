require "rails_helper"

# Where the signed-in user is in the flow and what they have finished, for the web app's home
# redirect, sign-in redirect and done page. The step is worked out from the saved records, and
# identity comes back as a status only, never its values (R17, R19).
RSpec.describe "GET /onboarding", type: :request do
  let(:user_id) { SecureRandom.uuid }

  let(:assessment_data) do
    { "reason" => "Ongoing support after a recent move", "urgency" => "medium",
      "preferred_window" => "weekday mornings", "distress" => false, "notes" => "Prefers video calls" }
  end

  def fetch_onboarding(as: user_id, params: {})
    get "/onboarding", params: params, headers: auth_headers(as)
  end

  def body
    response.parsed_body["onboarding"]
  end

  def save_assessment(for_user: user_id)
    Assessment.create!(user_id: for_user, schema_version: "1", data: assessment_data)
  end

  def confirm_identity(source:, for_user: user_id)
    Onboarding.for_user(for_user).confirm_identity!(DocumentHelpers::CLEAN_FIELDS, source: source)
  end

  it "rejects a request with no token with a 401 envelope" do
    get "/onboarding"

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
  end

  describe "a user with no onboarding yet" do
    it "gets 200 with the chat step, no assessment and an unconfirmed identity" do
      fetch_onboarding

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        "step" => "chat",
        "assessment" => nil,
        "identity" => { "confirmed" => false, "source" => nil, "confirmed_at" => nil }
      )
    end

    it "is read-only: the GET writes no onboarding row" do
      expect { fetch_onboarding }.not_to change(Onboarding, :count)
      expect(response).to have_http_status(:ok)
    end

    it "ignores an unsaved assessment draft in the conversation" do
      Conversation.for_user(user_id).update!(assessment_draft: { "reason" => "Half-finished" })

      fetch_onboarding

      expect(body["assessment"]).to be_nil
      expect(body["step"]).to eq("chat")
    end
  end

  describe "the current step follows the user's progress" do
    it "is identity once the assessment is saved, and returns the saved assessment" do
      save_assessment

      fetch_onboarding

      expect(body["step"]).to eq("identity")
      expect(body["assessment"]).to eq(assessment_data)
    end

    it "stays identity while an upload is pending confirmation" do
      save_assessment
      onboarding = Onboarding.for_user(user_id)
      onboarding.document_uploads.create!(storage_key: "#{user_id}/#{SecureRandom.uuid}.jpg", status: "pending",
                                          expires_at: 1.hour.from_now)

      fetch_onboarding

      expect(body["step"]).to eq("identity")
      expect(body["identity"]["confirmed"]).to be(false)
    end

    it "is schedule once the identity is confirmed from the ID photo" do
      save_assessment
      freeze_time do
        confirm_identity(source: "ocr")

        fetch_onboarding

        expect(body["step"]).to eq("schedule")
        expect(body["identity"]).to eq(
          "confirmed" => true, "source" => "ocr", "confirmed_at" => Time.current.utc.iso8601
        )
      end
    end

    it "reports identity entered by hand as source manual" do
      save_assessment
      confirm_identity(source: "manual")

      fetch_onboarding

      expect(body["identity"]).to include("confirmed" => true, "source" => "manual")
      expect(body["identity"]["confirmed_at"]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z\z/)
    end

    it "is done once the user has an active booking" do
      save_assessment
      confirm_identity(source: "ocr")
      create_booking(user_id: user_id)

      fetch_onboarding

      expect(body["step"]).to eq("done")
    end

    it "goes back to schedule after the booking is cancelled" do
      save_assessment
      confirm_identity(source: "ocr")
      create_booking(user_id: user_id, status: "cancelled")

      fetch_onboarding

      expect(body["step"]).to eq("schedule")
    end

    it "R16: moves on to schedule when the user skipped the chat and entered details by hand" do
      confirm_identity(source: "manual")

      fetch_onboarding

      expect(body["step"]).to eq("schedule")
      expect(body["assessment"]).to be_nil
    end
  end

  describe "no identity values in the payload (R17)" do
    before do
      save_assessment
      confirm_identity(source: "ocr")
      fetch_onboarding
    end

    it "returns only the step, the assessment and the identity status" do
      expect(response.parsed_body.keys).to eq([ "onboarding" ])
      expect(body.keys).to contain_exactly("step", "assessment", "identity")
      expect(body["identity"].keys).to contain_exactly("confirmed", "source", "confirmed_at")
    end

    it "never includes the name, date of birth or address" do
      expect(response).to have_http_status(:ok)
      DocumentHelpers::CLEAN_FIELDS.each_value do |value|
        expect(response.body).not_to include(value)
      end
      expect(response.body).not_to include("full_name", "date_of_birth", "address")
    end
  end

  describe "only the token's user (R19)" do
    let(:other_id) { SecureRandom.uuid }

    before do
      save_assessment(for_user: other_id)
      confirm_identity(source: "ocr", for_user: other_id)
      create_booking(user_id: other_id)
    end

    it "does not see another user's progress" do
      fetch_onboarding

      expect(body["step"]).to eq("chat")
      expect(body["assessment"]).to be_nil
      expect(body["identity"]["confirmed"]).to be(false)
    end

    it "ignores a user_id param naming another user" do
      fetch_onboarding(params: { user_id: other_id })

      expect(body["step"]).to eq("chat")
      expect(body["assessment"]).to be_nil
    end

    it "returns the other user's own progress to them" do
      fetch_onboarding(as: other_id)

      expect(body["step"]).to eq("done")
      expect(body["assessment"]).to eq(assessment_data)
    end
  end
end
