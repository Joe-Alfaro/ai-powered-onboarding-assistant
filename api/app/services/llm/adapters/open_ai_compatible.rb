module Llm
  module Adapters
    # Groq, Gemini and Ollama through their OpenAI-compatible chat completions endpoints, with
    # structured output from a JSON-schema response format.
    class OpenAiCompatible < Base
      SCHEMA_NAME = "respond".freeze

      # base_url is the API root, ending before /chat/completions. api_key may be nil (Ollama).
      def initialize(provider:, base_url:, api_key:, model:)
        @provider = provider
        @base_url = base_url
        @api_key = api_key
        @model = model
      end

      private

      def endpoint
        "#{@base_url.delete_suffix('/')}/chat/completions"
      end

      def headers
        @api_key.present? ? { "Authorization" => "Bearer #{@api_key}" } : {}
      end

      def request_body(payload)
        {
          model: model,
          messages: [ { role: "system", content: payload.system }, *payload.messages ],
          response_format: { type: "json_schema", json_schema: { name: SCHEMA_NAME, schema: payload.response_schema } }
        }
      end

      def usage(body)
        token_usage(body, "prompt_tokens", "completion_tokens")
      end

      def structured_output(body)
        content = Array(body["choices"]).first&.dig("message", "content")
        raise Llm::InvalidResponseError, "#{provider} returned no message" unless content.is_a?(String)

        json_object(content)
      end
    end
  end
end
