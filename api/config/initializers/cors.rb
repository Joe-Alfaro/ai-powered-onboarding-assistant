# The web app calls the API from the browser on another origin, so the API allows WEB_ORIGIN and
# no other (see WebOrigins). The bearer token is sent in the Authorization header, so credentials
# stay off. Inserted first, so preflights and early errors (such as the upload limit's 413) carry
# the CORS headers too.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*WebOrigins.from_env)

    resource "*",
      headers: %w[Authorization Content-Type],
      methods: %i[get post put patch delete options head],
      credentials: false,
      max_age: 600
  end
end
