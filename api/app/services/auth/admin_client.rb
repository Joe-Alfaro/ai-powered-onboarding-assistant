require "net/http"

module Auth
  # The Supabase Auth admin API, with the server's service role key. Used only to delete a user's
  # Auth account when they ask for deletion (R13). No retries and no debug output.
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
      request["Authorization"] = "Bearer #{@service_key}"
      request["apikey"] = @service_key
      response = perform(request)
      raise Error, "Supabase Auth returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess) || response.code == "404"
    end

    private

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
