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
        "assessment" => nil, "scheduling" => nil, "choices" => [])
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

    describe "R16: one overall deadline across the first call, the retry and the fallback provider" do
      let(:invalid_answer) { { "reply" => "Not the response schema" } }

      # The user gets the "try again" or "continue manually" choice: the 503 envelope with both
      # actions, or a 200 fallback reply that offers manual entry.
      def expect_failure_choice
        if response.status == 503
          expect(body.dig("error", "actions")).to eq(ChatHelpers::WIRE_ERROR_ACTIONS)
        else
          expect(response).to have_http_status(:ok)
          expect(body["actions"]).to include("manual_entry")
          expect(body["reply"]).not_to match(ChatHelpers::BOOKING_CLAIM)
        end
      end

      it "R16: answers within 10 s when a slow invalid answer is retried and the retry hangs" do
        slow = FakeLlmAdapter.new.respond_after(5, invalid_answer).hang
        allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: slow))

        seconds = elapsed_seconds { post_message("What happens next?") }

        expect(seconds).to be < 10
        expect_failure_choice
      end

      it "R16: answers within 10 s when the primary hangs, the fallback answers invalid and the retry hangs too" do
        primary = FakeLlmAdapter.new.hang.hang
        fallback = FakeLlmAdapter.new.respond_after(2.5, invalid_answer).hang
        allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: primary, fallback: fallback))

        seconds = elapsed_seconds { post_message("What happens next?") }

        expect(seconds).to be < 10
        expect_failure_choice
      end

      it "R16: never gives the LLM more than the time left before the deadline" do
        slow = FakeLlmAdapter.new.respond_after(4, invalid_answer).hang
        allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: slow))

        post_message("What happens next?")

        # 4 s spent on the first call leaves under 6 s for the retry.
        expect(slow.timeouts.drop(1)).to all(be < 6)
        expect_failure_choice
      end
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

  # R22: the request's log line says how many LLM calls it made and how long they took, so a slow
  # chat can be told apart from a retry, a fallback or database time. No message content.
  describe "R22: LLM calls in the request log" do
    def chat_log_entry(message)
      lines = log_lines(capture_logs { post_message(message) })
      lines.map { |line| JSON.parse(line) }.find { |entry| entry["path"] == "/chat/messages" }
    end

    it "R22: logs one call and its time for a plain answer" do
      entry = chat_log_entry("What happens next?")

      expect(entry).to include("llm_calls" => 1, "llm_ms" => be_a(Numeric).and(be >= 0))
      expect(entry.to_s).not_to include("What happens next?")
    end

    it "R22: counts the retry after an invalid answer" do
      llm.respond_with("reply" => "Not the response schema")

      expect(chat_log_entry("What happens next?")).to include("llm_calls" => 2)
    end

    it "R22: counts the fallback provider's call after the primary fails" do
      fallback = FakeLlmAdapter.new.always_respond_with(llm_output("ask-question"))
      allow(Llm::Client).to receive(:from_env)
        .and_return(Llm::Client.new(primary: FakeLlmAdapter.new.fail_with(Llm::ServerError), fallback: fallback))

      expect(chat_log_entry("What happens next?")).to include("llm_calls" => 2, "status" => 200)
    end

    it "R22: still logs the calls when the LLM fails" do
      allow(Llm::Client).to receive(:from_env)
        .and_return(Llm::Client.new(primary: FakeLlmAdapter.new.fail_with(Llm::ServerError)))

      expect(chat_log_entry("What happens next?")).to include("llm_calls" => 1, "status" => 503)
    end

    it "R22: logs no LLM calls for an empty message, which skips the LLM" do
      expect(chat_log_entry("")).to include("llm_calls" => 0, "llm_ms" => 0)
    end
  end
end
