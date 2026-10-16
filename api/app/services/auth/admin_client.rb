require "net/http"

module Auth
  # The Supabase Auth admin API, with the server's service role key. Used to delete a user's Auth
  # account when they ask for deletion (R13) and by the seed to create the demo users (R32). No
  # retries and no debug output.
  class AdminClient
    # Supabase Auth couldn't be reached or refused the call.
    class Error < StandardError; end

    TIMEOUT_SECONDS = 10

    def self.default
      new(url: "#{ENV.fetch("SUPABASE_URL")}/auth/v1", service_key: ENV.fetch("SUPABASE_SERVICE_ROLE_KEY"))
    end

    def initialize(url:, service_key:)
      @url = url
      @service_key = service_key
    end

    # Deletes the Auth user. A user who is already gone counts as deleted.
    def delete_user(user_id)
      request = Net::HTTP::Delete.new(URI("#{@url}/admin/users/#{ERB::Util.url_encode(user_id)}"))
      authorize(request)
      response = perform(request)
      raise Error, "Supabase Auth returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess) || response.code == "404"
    end

    # Creates a confirmed email and password user. Returns :created, or :exists when a user with that
    # email is already registered, so the seed can run again.
    def create_user(email:, password:)
      request = Net::HTTP::Post.new(URI("#{@url}/admin/users"))
      authorize(request)
      request["Content-Type"] = "application/json"
      request.body = { email: email, password: password, email_confirm: true }.to_json
      response = perform(request)
      return :created if response.is_a?(Net::HTTPSuccess)
      return :exists if already_registered?(response)

      raise Error, "Supabase Auth returned HTTP #{response.code}"
    end

    private

    def authorize(request)
      request["Authorization"] = "Bearer #{@service_key}"
      request["apikey"] = @service_key
    end

    # Supabase Auth answers 422 email_exists; older versions only say so in the message.
    def already_registered?(response)
      return false unless response.code == "422"

      body = JSON.parse(response.body.to_s)
      body["error_code"] == "email_exists" || body["msg"].to_s.include?("already been registered")
    rescue JSON::ParserError
      false
    end

    def perform(request)
      uri = request.uri
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT_SECONDS,
                      read_timeout: TIMEOUT_SECONDS, write_timeout: TIMEOUT_SECONDS, max_retries: 0) do |http|
        http.request(request)
      end
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
      raise Error, "Supabase Auth could not be reached (#{error.class})"
    end
  end
end
