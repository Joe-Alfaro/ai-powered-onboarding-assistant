# One JSON line per request (R31). Lograge logs no params and strips the query string from the
# path, so request data stays out of the logs (R15). ErrorHandling adds the request ID and, for
# failed requests, the error class and code.
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options = lambda do |event|
    event.payload.slice(:request_id, :error_class, :error_code, :error_backtrace)
  end
end
