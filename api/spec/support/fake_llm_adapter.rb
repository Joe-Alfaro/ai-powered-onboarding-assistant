# A scripted stand-in for an LLM adapter (Llm::Adapters::*), for specs that need an LLM without
# HTTP. Queue steps; each #complete call takes the next one.
#
#   adapter = FakeLlmAdapter.new
#     .respond_with("intent" => "ask-question", "assessment_fields" => {}, "reply" => "Hi")
#     .fail_with(Llm::RateLimitError)
#     .hang
#   client = Llm::Client.new(primary: adapter)
#   adapter.call_count # => number of #complete calls so far
#
# `hang` simulates a provider that never answers: it sleeps for the timeout it was given, then
# raises Llm::TimeoutError, so the wall-clock budget is real. For an instant timeout, use
# `fail_with(Llm::TimeoutError)`. `always_respond_with` sets the step used once the queue is empty.
class FakeLlmAdapter
  Call = Struct.new(:payload, :timeout)

  attr_reader :provider, :model, :calls

  def initialize(provider: "fake", model: "fake-model")
    @provider = provider
    @model = model
    @script = []
    @default_step = nil
    @calls = []
  end

  def respond_with(data)
    @script << [ :respond, data ]
    self
  end

  def always_respond_with(data)
    @default_step = [ :respond, data ]
    self
  end

  def fail_with(error)
    @script << [ :fail, error ]
    self
  end

  def hang
    @script << [ :hang ]
    self
  end

  def complete(payload, timeout:)
    calls << Call.new(payload, timeout)
    kind, value = @script.shift || @default_step || raise("FakeLlmAdapter has no scripted step left")

    case kind
    when :respond then Llm::Response.new(data: value.deep_stringify_keys, provider: provider, model: model)
    when :fail then raise value
    when :hang
      sleep timeout
      raise Llm::TimeoutError
    end
  end

  def call_count
    calls.size
  end

  def payloads
    calls.map(&:payload)
  end

  def timeouts
    calls.map(&:timeout)
  end
end
