module Perf
  # Reads server times back from Lograge's JSON request lines (R24 check 1), by request ID. The
  # log can be the local server's output or a copy of the deployed service's logs; lines that
  # aren't a JSON object with a duration are skipped.
  class LogrageDurations
    def initialize(log_text)
      @log_text = log_text
    end

    # { request_id => duration in ms } for each ID that has a Lograge line, in the order given.
    def for_request_ids(ids)
      found = durations
      ids.filter_map { |id| [ id, found[id] ] if found.key?(id) }.to_h
    end

    private
      def durations
        @log_text.each_line.with_object({}) do |line, found|
          entry = parse(line)
          next unless entry && entry["request_id"] && entry["duration"].is_a?(Numeric)

          found[entry["request_id"]] = entry["duration"]
        end
      end

      def parse(line)
        start = line.index("{")
        return unless start

        parsed = JSON.parse(line[start..])
        parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
  end
end
