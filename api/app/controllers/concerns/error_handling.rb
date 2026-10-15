# The single rescue_from layer (R30): every failure becomes the JSON envelope
# `{ error: { code, message, actions } }`, so no endpoint renders a default error page. The error
# class goes into the request's log line; its message never does, because it can hold personal
# data (R15, R31).
module ErrorHandling
  extend ActiveSupport::Concern

  KNOWN_ERRORS = {
    ActionController::RoutingError =>
      [ 404, "not_found", "We couldn't find that.", [] ],
    ActiveRecord::RecordNotFound =>
      [ 404, "not_found", "We couldn't find that.", [] ],
    ActionController::ParameterMissing =>
      [ 400, "invalid_request", "The request is missing some required information.", [] ],
    ActionDispatch::Http::Parameters::ParseError =>
      [ 400, "invalid_request", "The request couldn't be read.", [] ],
    ActiveRecord::RecordInvalid =>
      [ 422, "validation_failed", "Some details aren't valid. Please check them and try again.", [] ],
    Auth::JwtVerifier::InvalidToken =>
      [ 401, "unauthorized", "Please sign in again.", [] ],
    Auth::JwtVerifier::JwksUnavailable =>
      [ 503, "auth_unavailable", "We can't check your sign-in right now. Please try again shortly.", [ "retry" ] ],
    Storage::Client::Error =>
      [ 503, "storage_unavailable", "We can't save or show your photo right now. Please try again shortly.", [ "retry", "manual_entry" ] ],
    # Covers DatabaseConnectionError and ConnectionTimeoutError, which subclass it.
    ActiveRecord::ConnectionNotEstablished =>
      [ 503, "database_unavailable", "We can't reach our database right now. Please try again shortly.", [ "retry" ] ]
  }.freeze

  INTERNAL_ERROR = [ 500, "internal_error", "Something went wrong on our side. Please try again.", [ "retry" ] ].freeze

  included do
    # Handlers declared later win, so the catch-all comes first.
    rescue_from(StandardError) { |error| render_error(error, api_error_for(INTERNAL_ERROR), log_backtrace: true) }
    KNOWN_ERRORS.each do |error_class, details|
      rescue_from(error_class) { |error| render_error(error, api_error_for(details)) }
    end
    rescue_from(ApiError) { |error| render_error(error, error) }
  end

  private
    def api_error_for((status, code, message, actions))
      ApiError.new(status: status, code: code, message: message, actions: actions)
    end

    def render_error(error, api_error, log_backtrace: false)
      @error_log = { error_class: error.class.name, error_code: api_error.code }
      # Backtrace lines are file paths and line numbers only, so they're safe to log.
      @error_log[:error_backtrace] = Rails.backtrace_cleaner.clean(Array(error.backtrace)).first(5) if log_backtrace
      render json: api_error.to_envelope, status: api_error.status
    end

    # Adds fields to the request's single Lograge line.
    def append_info_to_payload(payload)
      super
      payload[:request_id] = request.request_id
      payload.merge!(@error_log) if @error_log
    end
end
