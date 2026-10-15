require "net/http"

module Storage
  # The private Supabase Storage bucket, through its REST API with the server's service role key
  # (R17). Objects are never public: the only way to view one is a short-lived signed URL. No
  # retries and no debug output, because request bodies are ID images.
  class Client
    # Storage couldn't be reached or refused the call.
    class Error < StandardError; end

    TIMEOUT_SECONDS = 10

    def self.default
      new(
        url: "#{ENV.fetch("SUPABASE_URL")}/storage/v1",
        bucket: ENV.fetch("STORAGE_BUCKET"),
        service_key: ENV.fetch("SUPABASE_SERVICE_ROLE_KEY")
      )
    end

    def initialize(url:, bucket:, service_key:)
      @url = url
      @bucket = bucket
      @service_key = service_key
    end

    def upload(key, io, content_type:)
      request = Net::HTTP::Post.new(object_uri(key))
      request["Content-Type"] = content_type
      request["x-upsert"] = "false"
      request.body_stream = io
      request["Content-Length"] = io.size.to_s
      expect_success(perform(request))
    end

    # Deletes the object. An object that is already gone counts as deleted.
    def delete(key)
      response = perform(Net::HTTP::Delete.new(object_uri(key)))
      expect_success(response) unless missing?(response)
    end

    # An absolute URL that shows the object for expires_in seconds.
    def signed_url(key, expires_in:)
      request = Net::HTTP::Post.new(URI("#{@url}/object/sign/#{@bucket}/#{escape(key)}"))
      request["Content-Type"] = "application/json"
      request.body = { expiresIn: expires_in }.to_json
      response = expect_success(perform(request))
      "#{@url}#{JSON.parse(response.body).fetch("signedURL")}"
    rescue JSON::ParserError, KeyError
      raise Error, "Storage returned no signed URL"
    end

    private

    def object_uri(key)
      URI("#{@url}/object/#{@bucket}/#{escape(key)}")
    end

    def escape(key)
      key.split("/").map { |part| ERB::Util.url_encode(part) }.join("/")
    end

    def perform(request)
      request["Authorization"] = "Bearer #{@service_key}"
      uri = request.uri
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT_SECONDS,
                      read_timeout: TIMEOUT_SECONDS, write_timeout: TIMEOUT_SECONDS, max_retries: 0) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
      raise Error, "Storage could not be reached (#{error.class})"
    end

    def expect_success(response)
      raise Error, "Storage returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response
    end

    # Storage reports a missing object as a 400 whose body carries statusCode "404".
    def missing?(response)
      return true if response.code == "404"

      response.code == "400" && JSON.parse(response.body.to_s)["statusCode"].to_s == "404"
    rescue JSON::ParserError
      false
    end
  end
end
