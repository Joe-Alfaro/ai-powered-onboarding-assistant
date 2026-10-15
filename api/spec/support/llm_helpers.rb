# Shared fixtures for the LLM client specs: a test response schema, a payload builder shortcut and
# canned provider responses for WebMock. Never use real keys here.
module LlmHelpers
  ANTHROPIC_URL = "https://api.anthropic.com/v1/messages".freeze
  GROQ_URL = "https://api.groq.com/openai/v1/chat/completions".freeze
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions".freeze
  OLLAMA_URL = "http://localhost:11434/v1/chat/completions".freeze

  PROVIDER_URLS = {
    "anthropic" => ANTHROPIC_URL,
    "groq" => GROQ_URL,
    "gemini" => GEMINI_URL,
    "ollama" => OLLAMA_URL
  }.freeze

  # Fake keys, one per provider, so a spec can check which key a request carried.
  TEST_KEYS = {
    "CLAUDE_API_KEY" => "test-claude-key",
    "GROQ_API_KEY" => "test-groq-key",
    "GEMINI_API_KEY" => "test-gemini-key"
  }.freeze

  RESPONSE_SCHEMA = {
    "type" => "object",
    "properties" => {
      "intent" => {
        "type" => "string",
        "enum" => %w[provide-details ask-question request-reschedule express-distress out-of-scope]
      },
      "assessment_fields" => {
        "type" => "object",
        "properties" => {
          "reason" => { "type" => "string" },
          "urgency" => { "type" => "string" },
          "preferred_window" => { "type" => "string" },
          "distress" => { "type" => "boolean" },
          "notes" => { "type" => "string" }
        }
      },
      "reply" => { "type" => "string" }
    },
    "required" => %w[intent assessment_fields reply]
  }.freeze

  STRUCTURED_REPLY = {
    "intent" => "ask-question",
    "assessment_fields" => {},
    "reply" => "Happy to help with that."
  }.freeze

  def build_llm_payload(turns: [ { role: "user", content: "What happens after I sign up?" } ],
                        identity: {}, assessment_draft: {}, system: "You are an onboarding assistant.")
    Llm::PayloadBuilder.new(identity: identity)
      .build(system: system, turns: turns, assessment_draft: assessment_draft, response_schema: RESPONSE_SCHEMA)
  end

  def llm_env(overrides = {})
    TEST_KEYS.merge(overrides)
  end

  def anthropic_body(data = STRUCTURED_REPLY)
    {
      id: "msg_test",
      type: "message",
      role: "assistant",
      model: "test-model",
      content: [ { type: "tool_use", id: "toolu_test", name: "respond", input: data } ],
      stop_reason: "tool_use"
    }.to_json
  end

  def openai_body(data = STRUCTURED_REPLY)
    content = data.is_a?(String) ? data : data.to_json
    {
      id: "chatcmpl-test",
      object: "chat.completion",
      choices: [ { index: 0, message: { role: "assistant", content: content }, finish_reason: "stop" } ]
    }.to_json
  end

  def success_body_for(provider, data = STRUCTURED_REPLY)
    provider == "anthropic" ? anthropic_body(data) : openai_body(data)
  end

  def stub_provider_success(provider, data = STRUCTURED_REPLY)
    stub_request(:post, PROVIDER_URLS.fetch(provider))
      .to_return(status: 200, body: success_body_for(provider, data), headers: { "Content-Type" => "application/json" })
  end

  def stub_provider_status(provider, status)
    stub_request(:post, PROVIDER_URLS.fetch(provider))
      .to_return(status: status, body: { error: { message: "stubbed #{status}" } }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def json_body(request)
    JSON.parse(request.body)
  end

  def elapsed_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end
end

RSpec.configure do |config|
  config.include LlmHelpers
end
