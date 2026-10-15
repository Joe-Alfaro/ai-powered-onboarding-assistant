require "net/http"

module Auth
  # Verifies Supabase Auth access tokens against the project's JWKS (R19). The JWKS is cached in
  # memory, refetched when it expires, and refetched early when a token names a key it doesn't
  # have yet, so a key rotation needs no restart.
  class JwtVerifier
    class InvalidToken < StandardError; end
    class JwksUnavailable < StandardError; end

    Identity = Data.define(:user_id, :admin) do
      def admin? = admin
    end

    # Asymmetric only: a shared-secret (HS256) or unsigned token must never verify.
    ALGORITHMS = %w[ES256 RS256].freeze
    AUDIENCE = "authenticated".freeze
    JWKS_TTL = 10.minutes
    # An unknown kid triggers a refetch at most this often, so forged kids can't make every
    # request call the JWKS endpoint.
    UNKNOWN_KID_REFETCH_INTERVAL = 1.minute
    HTTP_TIMEOUT_SECONDS = 3

    # The app-wide verifier, shared so every request uses the same JWKS cache.
    def self.default
      @default ||= new(jwks_url: ENV.fetch("SUPABASE_JWKS_URL"), issuer: "#{ENV.fetch('SUPABASE_URL')}/auth/v1")
    end

    def initialize(jwks_url:, issuer:, audience: AUDIENCE)
      @jwks_uri = URI(jwks_url)
      @issuer = issuer
      @audience = audience
      @mutex = Mutex.new
      @jwks = nil
      @fetched_at = nil
    end

    def verify(token)
      payload, = JWT.decode(token.to_s, nil, true,
        algorithms: ALGORITHMS, jwks: method(:jwks),
        iss: @issuer, verify_iss: true, aud: @audience, verify_aud: true,
        required_claims: %w[exp sub])
      user_id = payload["sub"]
      raise InvalidToken, "sub is blank" unless user_id.is_a?(String) && user_id.present?

      # Only app_metadata counts: users can edit user_metadata, and the top-level role claim is
      # Postgres' role, not the app's.
      Identity.new(user_id: user_id, admin: payload.dig("app_metadata", "role") == "admin")
    rescue JWT::DecodeError => e
      raise InvalidToken, e.class.name
    end

    private
      # Called by JWT.decode; `kid_not_found` is set when the token's kid isn't in the set given.
      def jwks(options)
        @mutex.synchronize do
          refresh if @jwks.nil? || age > JWKS_TTL || (options[:kid_not_found] && age > UNKNOWN_KID_REFETCH_INTERVAL)
          @jwks
        end
      end

      def age
        Time.current - @fetched_at
      end

      def refresh
        @jwks = fetch_jwks
        @fetched_at = Time.current
      rescue JwksUnavailable
        # Keep verifying with the keys we have rather than locking every user out.
        raise if @jwks.nil?
      end

      def fetch_jwks
        response = Net::HTTP.start(@jwks_uri.host, @jwks_uri.port, use_ssl: @jwks_uri.scheme == "https",
          open_timeout: HTTP_TIMEOUT_SECONDS, read_timeout: HTTP_TIMEOUT_SECONDS) do |http|
          http.get(@jwks_uri.request_uri)
        end
        raise JwksUnavailable, "JWKS responded #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JWT::JWK::Set.new(JSON.parse(response.body))
      rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError, JWT::JWKError => e
        raise JwksUnavailable, e.class.name
      end
  end
end
