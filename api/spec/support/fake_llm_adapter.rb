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
# `fail_with(Llm::TimeoutError)`. `respond_after(seconds, data)` answers after a delay, like a slow
# provider; when the delay is longer than the timeout it was given, it waits out the timeout and
# raises Llm::TimeoutError instead. `always_respond_with` sets the step used once the queue is empty;
# `respond_by { |payload| data }` does the same with an answer computed from each payload. Pass
# `usage: { input_tokens:, output_tokens: }` to any respond step to report token usage.
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

  # Callers may pass the output as bare keywords, so `usage:` is split off the rest.
  def respond_with(data = nil, usage: nil, **output)
    @script << [ :respond, data || output, usage ]
    self
  end

  def always_respond_with(data = nil, usage: nil, **output)
    @default_step = [ :respond, data || output, usage ]
    self
  end

  def respond_by(usage: nil, &block)
    @default_step = [ :respond_by, block, usage ]
    self
  end

  def respond_after(seconds, data = nil, usage: nil, **output)
    @script << [ :respond_after, [ seconds, data || output ], usage ]
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
    kind, value, usage = @script.shift || @default_step || raise("FakeLlmAdapter has no scripted step left")

    case kind
    when :respond then response(value, usage)
    when :respond_by then response(value.call(payload), usage)
    when :respond_after then respond_after_delay(*value, usage, timeout)
    when :fail then raise value
    when :hang
      sleep timeout
      raise Llm::TimeoutError
    end
  end

  def respond_after_delay(seconds, data, usage, timeout)
    if seconds > timeout
      sleep timeout
      raise Llm::TimeoutError
    end

    sleep seconds
    response(data, usage)
  end

  # Usage is passed only when scripted, so specs that don't need it don't depend on it.
  def response(data, usage)
    Llm::Response.new(data: data.deep_stringify_keys, provider: provider, model: model, **({ usage: usage } if usage).to_h)
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
