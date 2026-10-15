require "rails_helper"

# POST /chat/messages: the HTTP face of Chat::Orchestrator. The LLM is a FakeLlmAdapter behind
# Llm::Client.from_env; consent and scheduling are stubbed at their seams.
RSpec.describe "POST /chat/messages", type: :request do
  let(:chat_user_id) { SecureRandom.uuid }
  let(:headers) { auth_headers(chat_user_id) }
  let(:llm) { FakeLlmAdapter.new.always_respond_with(llm_output("ask-question", reply: "Happy to help with that.")) }

  before { allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: llm)) }

  def post_message(message, headers: self.headers, **extra)
    post "/chat/messages", params: { message: message, **extra }, headers: headers, as: :json
  end

  def body
    response.parsed_body
  end

  describe "auth" do
    it "R19: requires a bearer token" do
      post_message("Hello", headers: {})

      expect(response).to have_http_status(:unauthorized)
      expect(body.dig("error", "code")).to eq("unauthorized")
      expect(llm.call_count).to eq(0)
    end

    it "R19: takes the user from the token, not from the request" do
      other_user = SecureRandom.uuid
      llm.respond_with(llm_output("provide-details", fields: { "reason" => "Can't sleep" }))
      post_message("I can't sleep", headers: auth_headers(other_user))

      post_message("What happens next?", user_id: other_user)

      expect(response).to have_http_status(:ok)
      expect(llm.payloads.last.system).not_to include("Can't sleep")
    end
  end

  describe "R1, R9: a successful message" do
    it "R1: returns the reply, intent, trigger, actions, assessment and scheduling keys" do
      post_message("What happens next?")

      expect(response).to have_http_status(:ok)
      expect(body).to include("reply" => "Happy to help with that.", "intent" => "ask-question", "trigger" => nil,
        "assessment" => nil, "scheduling" => nil)
      expect(body["actions"]).to be_a(Array)
    end

    it "R9: carries trigger high-stress-intent for an express-distress message" do
      llm.respond_with(llm_output("express-distress", reply: "I'm sorry, let's go slowly."))

      post_message("I'm completely overwhelmed")

      expect(body["trigger"]).to eq("high-stress-intent")
    end
  end

  it "R2: returns the saved assessment as a summary when the last required field arrives" do
    conversation = scripted_conversations.first
    conversation["turns"].each do |turn|
      llm.respond_with(turn["scripted_llm"])
      post_message(turn["user"])
    end

    expect(response).to have_http_status(:ok)
    expect(body["assessment"]).to include(conversation["expected_assessment"])
  end

  it "R36: passes the chosen booking and slot to Scheduling::Booker and returns its result" do
    booking_id = SecureRandom.uuid
    slot = { id: SecureRandom.uuid, starts_at: "2030-03-05T14:30:00Z", ends_at: "2030-03-05T15:00:00Z" }
    result = booker_result(outcome: :rescheduled, success: true, slot: slot, booking_id: booking_id)
    _, booker = stub_booker(result)
    llm.respond_with(llm_output("request-reschedule", reply: "Booked you for Friday at 3pm!"))

    post_message("Move me to that slot", booking_id: booking_id, slot_id: slot[:id])

    expect(booker).to have_received(:reschedule).with(booking_id: booking_id, slot_id: slot[:id])
    expect(body["scheduling"]).to eq(result.to_h.deep_stringify_keys)
    expect(body["reply"]).not_to match(/friday|3\s*pm/i)
  end

  describe "R3 [gotcha]: hostile input gets a fallback reply, not an error" do
    ChatHelpers.adversarial_inputs.each do |input|
      it "R3: #{input['id']} returns 200 with a reply" do
        post_message(input["message"])

        expect(response).to have_http_status(:ok)
        expect(body["reply"]).to be_present
        expect(body).not_to have_key("error")
      end
    end

    it "R2, R3: a fallback after malformed LLM output offers manual_entry, the web's action name" do
      allow(Llm::Client).to receive(:from_env)
        .and_return(Llm::Client.new(primary: FakeLlmAdapter.new.always_respond_with({ "reply" => "🤔" })))

      post_message("😀🙏🔥💯🫠")

      expect(response).to have_http_status(:ok)
      expect(body["actions"]).to include("manual_entry")
      expect(body["actions"]).not_to include("continue_manually")
    end

    it "R3: a request with no message at all still gets a reply" do
      post "/chat/messages", params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body["reply"]).to be_present
    end
  end

  it "R13: returns 403 consent_withdrawn and makes no LLM call once consent is withdrawn" do
    stub_consent(true)

    post_message("What happens next?")

    expect(response).to have_http_status(:forbidden)
    expect(body.dig("error", "code")).to eq("consent_withdrawn")
    expect(llm.call_count).to eq(0)
  end

  describe "R16: LLM failure returns the error envelope with retry and manual_entry actions" do
    {
      "a timeout" => Llm::TimeoutError,
      "a 5xx" => Llm::ServerError,
      "a 429" => Llm::RateLimitError,
      "a connection failure" => Llm::ConnectionError
    }.each do |description, error_class|
      it "R16: maps #{description} to a 503 envelope and doesn't retry it" do
        failing = FakeLlmAdapter.new.fail_with(error_class).always_respond_with(llm_output("ask-question"))
        allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: failing))

        post_message("What happens next?")

        expect(response).to have_http_status(:service_unavailable)
        expect(body.fetch("error")).to include("code" => error_class.new.code,
          "message" => a_string_matching(/\S/), "actions" => ChatHelpers::WIRE_ERROR_ACTIONS)
        expect(failing.call_count).to eq(1)
      end
    end

    it "R16: answers within 10 s when the provider hangs" do
      hanging = FakeLlmAdapter.new.hang.always_respond_with(llm_output("ask-question"))
      allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: hanging))

      seconds = elapsed_seconds { post_message("What happens next?") }

      expect(seconds).to be < 10
      expect(response).to have_http_status(:service_unavailable)
      expect(body.dig("error", "actions")).to eq(ChatHelpers::WIRE_ERROR_ACTIONS)
    end

    it "R16: makes no commitment in the error envelope" do
      allow(Llm::Client).to receive(:from_env)
        .and_return(Llm::Client.new(primary: FakeLlmAdapter.new.fail_with(Llm::ServerError)))

      post_message("Did you book me for Friday?")

      expect(response).to have_http_status(:service_unavailable)
      expect(body).not_to have_key("reply")
      expect(response.body).not_to match(ChatHelpers::BOOKING_CLAIM)
    end
  end
end
