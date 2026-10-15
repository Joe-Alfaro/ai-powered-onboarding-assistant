require "json"
require "logger"
require "time"

# Writes every log entry as one JSON object per line (R31). A message that is already a JSON
# object (Lograge's request line) is merged in as fields; anything else becomes `message`.
class JsonLogFormatter < ::Logger::Formatter
  def call(severity, time, _progname, message)
    entry = { level: severity, time: time.utc.iso8601(3) }.merge(fields(message))
    "#{JSON.generate(entry)}\n"
  end

  private
    def fields(message)
      case message
      when Hash then message
      when String then json_object(message) || { message: message }
      when Exception then { error_class: message.class.name }
      else { message: message.inspect }
      end
    end

    def json_object(text)
      return unless text.start_with?("{")

      parsed = JSON.parse(text)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
end
