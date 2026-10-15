# Every endpoint requires a verified Supabase token by default (R19). The current user comes
# only from the token's sub, never from a param or header. Public endpoints opt out with
# `skip_before_action :authenticate!`; admin endpoints add `before_action :require_admin!`.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private
    attr_reader :current_identity

    def current_user_id
      current_identity.user_id
    end

    def authenticate!
      scheme, token = request.authorization.to_s.split(" ", 2)
      raise Auth::JwtVerifier::InvalidToken, "no bearer token" unless scheme&.casecmp?("Bearer") && token.present?

      @current_identity = Auth::JwtVerifier.default.verify(token)
    end

    def require_admin!
      raise ApiError.forbidden unless current_identity.admin?

      AuditEvent.record!(user_id: current_user_id, action: "admin_access:#{controller_path}##{action_name}")
    end
end
