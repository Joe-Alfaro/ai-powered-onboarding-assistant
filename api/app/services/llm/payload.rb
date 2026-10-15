module Llm
  # The only thing an adapter will send. Only Llm::PayloadBuilder can construct one, so every
  # outgoing request has been through its redaction and allowlist (R20).
  class Payload
    attr_reader :system, :messages, :response_schema

    private_class_method :new

    def initialize(system:, messages:, response_schema:)
      @system = system.freeze
      @messages = messages.map(&:freeze).freeze
      @response_schema = response_schema
      freeze
    end
  end
end
