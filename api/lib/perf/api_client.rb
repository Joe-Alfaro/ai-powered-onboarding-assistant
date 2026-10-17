require "net/http"

module Perf
  # A minimal HTTP client for the timing tasks: one signed-in user against PERF_BASE_URL. Each call
  # returns the response and the client-side time in ms, from just before the request is written
  # to the end of the response body, on a monotonic clock.
  class ApiClient
    Reply = Data.define(:status, :body, :request_id, :client_ms)

    TIMEOUT_SECONDS = 60

    def initialize(base_url:, token:)
      @base = URI(base_url)
      @token = token
    end

    def get(path) = perform(Net::HTTP::Get.new(path))
    def delete(path) = perform(Net::HTTP::Delete.new(path))

    def post_json(path, payload)
      request = Net::HTTP::Post.new(path)
      request["Content-Type"] = "application/json"
      request.body = payload.to_json
      perform(request)
    end

    def upload(path, file_path, content_type:)
      File.open(file_path, "rb") do |io|
        request = Net::HTTP::Post.new(path)
        request.set_form([ [ "file", io, { filename: File.basename(file_path), content_type: content_type } ] ],
                         "multipart/form-data")
        perform(request)
      end
    end

    private
      def perform(request)
        request["Authorization"] = "Bearer #{@token}"
        request["Accept"] = "application/json"
        Net::HTTP.start(@base.host, @base.port, use_ssl: @base.scheme == "https",
                        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response = http.request(request)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
          Reply.new(status: response.code.to_i, body: parse(response.body), request_id: response["X-Request-Id"],
                    client_ms: elapsed.round(1))
        end
      end

      def parse(body)
        body.present? ? JSON.parse(body) : {}
      rescue JSON::ParserError
        {}
      end
  end
end
