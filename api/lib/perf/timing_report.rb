module Perf
  # Summarizes a timing run: client-side times for every request, server times from the Lograge
  # lines when a log is given, and how many requests failed. Only successful requests count
  # towards the timings; failures are reported as a count and an error rate.
  class TimingReport
    def initialize(name:, replies:, success:, log_text: nil)
      @name = name
      @replies = replies
      @success = success
      @log_text = log_text
    end

    def to_h
      ok = @replies.select(&@success)
      {
        name: @name,
        runs: @replies.size,
        failures: @replies.size - ok.size,
        error_rate: Stats.rate(@replies.size - ok.size, @replies.size).round(3),
        statuses: @replies.map(&:status).tally,
        client_ms: Stats.summary(ok.map(&:client_ms)),
        server_ms: server_summary(ok)
      }
    end

    def lines
      report = to_h
      out = [ "#{@name}: #{report[:runs]} runs, #{report[:failures]} failed " \
              "(error rate #{(report[:error_rate] * 100).round(1)}%), statuses #{report[:statuses]}" ]
      out << "  client-side ms: #{format_summary(report[:client_ms])}"
      out << (report[:server_ms] ? "  server-side ms (Lograge duration): #{format_summary(report[:server_ms])}" :
                                   "  server-side ms: no PERF_LOG_FILE given")
      out
    end

    private
      def server_summary(ok)
        return unless @log_text

        found = LogrageDurations.new(@log_text).for_request_ids(ok.filter_map(&:request_id))
        Stats.summary(found.values).merge(missing_log_lines: ok.size - found.size)
      end

      def format_summary(summary)
        summary.map { |key, value| "#{key} #{value.inspect}" }.join(", ")
      end
  end
end
