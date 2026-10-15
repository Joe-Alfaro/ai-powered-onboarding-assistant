# Shared setup for the eval harness specs (R27, R28): a fake LLM that answers every committed eval
# message the way a perfect provider would, so a spec only scripts what it changes.
#
#   llm = eval_llm { |message| llm_output("ask-question") if message == "Who won the game?" }
#   report = Eval::ChatScorer.new(adapter: llm).call
module EvalHelpers
  CANDIDATES = {
    "claude-haiku" => { provider: "anthropic", model: "claude-haiku-4-5", variable: "CLAUDE_API_KEY" },
    "claude-sonnet" => { provider: "anthropic", model: "claude-sonnet-5-5", variable: "CLAUDE_API_KEY" },
    "groq" => { provider: "groq", model: Llm::Providers::DEFAULT_MODELS.fetch("groq"), variable: "GROQ_API_KEY" },
    "gemini" => { provider: "gemini", model: Llm::Providers::DEFAULT_MODELS.fetch("gemini"), variable: "GEMINI_API_KEY" },
    "ollama" => { provider: "ollama", model: Llm::Providers::DEFAULT_MODELS.fetch("ollama"), variable: "OLLAMA_BASE_URL" }
  }.freeze
  PROVIDER_VARIABLES = %w[
    LLM_PROVIDER LLM_MODEL LLM_FALLBACK_PROVIDER LLM_FALLBACK_MODEL
    CLAUDE_API_KEY GROQ_API_KEY GEMINI_API_KEY OLLAMA_BASE_URL PROVIDERS
  ].freeze
  BOOKING_BAIT_ID = "booking-claim-bait".freeze

  # The answer a perfect provider gives each committed eval message: the labeled intent for the
  # intent set, the scripted output for the conversations, and the redirect for anything else.
  def eval_answers
    answers = {}
    intent_set.each { |intent, utterances| utterances.each { |utterance| answers[utterance] = llm_output(intent) } }
    scripted_conversations.each { |conversation| conversation["turns"].each { |turn| answers[turn["user"]] = turn["scripted_llm"] } }
    answers
  end

  # A FakeLlmAdapter answering by the last user message. The block may return an output (or raise)
  # to override the perfect answer for that message; returning nil keeps it.
  def eval_llm(provider: "fake", model: "fake-model", usage: nil, &override)
    answers = eval_answers
    FakeLlmAdapter.new(provider: provider, model: model).respond_by(usage: usage) do |payload|
      message = last_user_message(payload)
      override&.call(message) || answers.fetch(message, llm_output("out-of-scope"))
    end
  end

  def last_user_message(payload)
    payload.messages.reverse.find { |message| message[:role] == "user" }[:content]
  end

  def adversarial_message(id)
    adversarial_inputs.find { |input| input["id"] == id }.fetch("message")
  end

  # Every message the eval sends, for checking that none leaks into the results files.
  def eval_messages
    intent_set.values.flatten +
      scripted_conversations.flat_map { |conversation| conversation["turns"].map { |turn| turn["user"] } } +
      adversarial_inputs.map { |input| input["message"] }.select(&:present?)
  end
end

RSpec.configure do |config|
  config.include EvalHelpers
end
