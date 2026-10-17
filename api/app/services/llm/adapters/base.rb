require "net/http"

module Llm
  module Adapters
    # Shared HTTP plumbing: one POST per call with the caller's timeout, no retries and no debug
    # output, and every failure mapped to a typed Llm::Error (R16).
    class Base
      attr_reader :provider, :model

      def complete(payload, timeout:)
        raise ArgumentError, "expected an Llm::Payload from Llm::PayloadBuilder" unless payload.is_a?(Payload)

        body = post(request_body(payload), timeout)
        Response.new(data: structured_output(body), provider: provider, model: model, usage: usage(body))
      end

      # Lists the provider's models, a cheap call that spends no completion quota. The health
      # check uses it to tell whether the provider is reachable and accepts the key (R31).
      def list_models(timeout:)
        send_request(Net::HTTP::Get.new(URI(models_endpoint), headers), timeout)
      end

      private

      # Token counts in the provider's own field names; nil when the provider reports none.
      def token_usage(body, input_key, output_key)
        input, output = body["usage"]&.values_at(input_key, output_key)
        return unless input.is_a?(Integer) && output.is_a?(Integer)

        { input_tokens: input, output_tokens: output }
      end

      def post(body, timeout)
        request = Net::HTTP::Post.new(URI(endpoint), headers.merge("Content-Type" => "application/json"))
        request.body = body.to_json
        send_request(request, timeout)
      end

      def send_request(request, timeout)
        uri = request.uri
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = http.write_timeout = timeout
        http.max_retries = 0
        # Request and response bodies carry user text, so debug output stays off everywhere.
        http.set_debug_output(nil)
        parse(http.request(request))
      rescue Timeout::Error
        raise Llm::TimeoutError, "#{provider} did not answer within #{timeout} s"
      rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise Llm::ConnectionError, "#{provider} could not be reached (#{error.class})"
      end

      def parse(response)
        status = response.code.to_i
        raise Llm::RateLimitError, "#{provider} rate limited the request (HTTP 429)" if status == 429
        raise Llm::ServerError, "#{provider} returned HTTP #{status}" if status >= 500
        raise Llm::RequestError, "#{provider} rejected the request (HTTP #{status})" unless status.between?(200, 299)

        json_object(response.body)
      end

      def json_object(text)
        parsed = JSON.parse(text.to_s)
        raise Llm::InvalidResponseError, "#{provider} did not return a JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError
        raise Llm::InvalidResponseError, "#{provider} did not return JSON"
      end
    end
  end
end
