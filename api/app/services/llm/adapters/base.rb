require "net/http"

module Llm
  module Adapters
    # Shared HTTP plumbing: one POST per call with the caller's timeout, no retries and no debug
    # output, and every failure mapped to a typed Llm::Error (R16).
    class Base
      attr_reader :provider, :model

      def complete(payload, timeout:)
        raise ArgumentError, "expected an Llm::Payload from Llm::PayloadBuilder" unless payload.is_a?(Payload)

        Response.new(data: structured_output(post(request_body(payload), timeout)), provider: provider, model: model)
      end

      private

      def post(body, timeout)
        uri = URI(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = http.write_timeout = timeout
        http.max_retries = 0
        # Request and response bodies carry user text, so debug output stays off everywhere.
        http.set_debug_output(nil)

        request = Net::HTTP::Post.new(uri, headers.merge("Content-Type" => "application/json"))
        request.body = body.to_json
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
