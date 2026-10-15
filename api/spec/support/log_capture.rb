# Captures what the app logs at :info and above (the production level) while the block runs,
# using the app logger's own formatter so the captured lines look like real log lines.
module LogCapture
  def capture_logs
    io = StringIO.new
    sink = ActiveSupport::Logger.new(io)
    sink.formatter = Rails.logger.formatter
    sink.level = :info
    Rails.logger.broadcast_to(sink)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(sink)
  end

  def log_lines(output)
    output.lines.map(&:strip).reject(&:empty?)
  end
end

RSpec.configure do |config|
  config.include LogCapture
end
