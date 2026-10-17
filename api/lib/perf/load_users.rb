require "net/http"

module Perf
  # Creates the load-test users in Supabase Auth and signs each in, for the k6 run and the timing
  # tasks (R22, R23, R24). The emails are fixed, so a rerun reuses the same users; the password
  # comes from the operator (PERF_USER_PASSWORD) and is never committed. Reserved domain, so no
  # mail ever leaves.
  class LoadUsers
    # Sign-in failed, for example because the users exist with a different password.
    class Error < StandardError; end

    EMAIL_FORMAT = "load-test-%02d@example.com".freeze
    TIMEOUT_SECONDS = 10

    def self.default(password:)
      url = ENV.fetch("SUPABASE_URL")
      service_key = ENV.fetch("SUPABASE_SERVICE_ROLE_KEY")
      new(auth: Auth::AdminClient.new(url: "#{url}/auth/v1", service_key: service_key),
          token_url: "#{url}/auth/v1/token?grant_type=password",
          api_key: ENV["SUPABASE_ANON_KEY"].presence || service_key, password: password)
    end

    def initialize(auth:, token_url:, api_key:, password:)
      @auth = auth
      @token_url = URI(token_url)
      @api_key = api_key
      @password = password
    end

    # [{ email:, access_token: }], one per user. Tokens last as long as the project's JWT expiry
    # (an hour by default), so create them just before a run.
    def call(count)
      (1..count).map do |index|
        email = format(EMAIL_FORMAT, index)
        @auth.create_user(email: email, password: @password)
        { email: email, access_token: sign_in(email) }
      end
    end

    private
      def sign_in(email)
        request = Net::HTTP::Post.new(@token_url)
        request["apikey"] = @api_key
        request["Content-Type"] = "application/json"
        request.body = { email: email, password: @password }.to_json
        response = Net::HTTP.start(@token_url.host, @token_url.port, use_ssl: @token_url.scheme == "https",
                                   open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) { |http| http.request(request) }
        raise Error, "Sign-in for #{email} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body).fetch("access_token")
      end
  end
end
