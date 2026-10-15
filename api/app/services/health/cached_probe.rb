module Health
  # Wraps a probe so repeated pings within the ttl reuse its last result instead of calling the
  # provider again (R31). Failures are cached too, so a down provider isn't hammered.
  class CachedProbe
    attr_reader :ttl

    def initialize(probe, ttl:)
      @probe = probe
      @ttl = ttl
      @mutex = Mutex.new
      @checked_at = nil
    end

    def call
      @mutex.synchronize do
        if @checked_at.nil? || Time.current - @checked_at > ttl
          @result = Check.healthy?(@probe)
          @checked_at = Time.current
        end
        @result
      end
    end
  end
end
