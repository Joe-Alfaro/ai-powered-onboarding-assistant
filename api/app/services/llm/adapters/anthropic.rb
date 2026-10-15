module Llm
  module Adapters
    # Claude through the Messages API, with structured output from one tool whose input schema is
    # the payload's response schema.
    class Anthropic < Base
      DEFAULT_BASE_URL = "https://api.anthropic.com".freeze
      API_VERSION = "2023-06-01".freeze
      MAX_TOKENS = 2048
      TOOL_NAME = "respond".freeze
      # Models that reject a forced tool_choice. They get "auto", an instruction to call the tool,
      # and low effort to keep within the 6 s timeout.
      AUTO_TOOL_CHOICE_MODELS = /\Aclaude-(?:sonnet-5-5|opus-5-5|fable-5-1|mythos-5-1)/

      def initialize(api_key:, model:, base_url: DEFAULT_BASE_URL)
        @provider = "anthropic"
        @api_key = api_key
        @model = model
        @base_url = base_url
      end

      private

      def endpoint
        "#{@base_url.delete_suffix('/')}/v1/messages"
      end

      def headers
        { "x-api-key" => @api_key, "anthropic-version" => API_VERSION }
      end

      def request_body(payload)
        body = {
          model: model,
          max_tokens: MAX_TOKENS,
          system: payload.system,
          messages: payload.messages,
          tools: [ { name: TOOL_NAME, description: "Give your structured answer.", input_schema: payload.response_schema } ]
        }
        return body.merge(tool_choice: { type: "tool", name: TOOL_NAME }) unless model.match?(AUTO_TOOL_CHOICE_MODELS)

        body.merge(system: "#{payload.system}\n\nAlways answer by calling the #{TOOL_NAME} tool.",
                   tool_choice: { type: "auto" }, output_config: { effort: "low" })
      end

      def structured_output(body)
        block = Array(body["content"]).find { |item| item["type"] == "tool_use" && item["name"] == TOOL_NAME }
        input = block&.dig("input")
        raise Llm::InvalidResponseError, "#{provider} answered without calling the #{TOOL_NAME} tool" unless input.is_a?(Hash)

        input
      end
    end
  end
end
