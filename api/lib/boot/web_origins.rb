# The origins allowed through CORS: WEB_ORIGIN, a comma-separated list. Required in production,
# where the web app and the API are separate services, so a missing value fails at boot instead of
# blocking every browser call. Development and test default to the local web app.
module WebOrigins
  # WEB_ORIGIN isn't set in production.
  class MissingError < StandardError; end

  LOCAL_DEFAULT = "http://localhost:3000".freeze

  def self.from_env(env = ENV, production: Rails.env.production?)
    origins = env.fetch("WEB_ORIGIN", "").split(",").map(&:strip).reject(&:empty?)
    return origins if origins.any?
    raise MissingError, "WEB_ORIGIN must be set in production (the web app's origin, for CORS)" if production

    [ LOCAL_DEFAULT ]
  end
end
