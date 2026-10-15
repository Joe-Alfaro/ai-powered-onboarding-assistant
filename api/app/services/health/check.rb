module Health
  # Reports app, database, storage, OCR and LLM status (R31). A probe is any callable; it's down
  # when it returns a falsy value or raises. Each dependency's status depends only on its own
  # probe, so breaking one changes only that entry.
  class Check
    # Storage, OCR and LLM probes call providers, so pings reuse a result for this long.
    PROVIDER_PROBE_TTL = 5.minutes

    # The app's registered probes. The database is checked on every ping, which also keeps
    # Supabase from pausing an idle project. Storage, OCR and LLM start as NotConfigured (down)
    # until their slices replace the placeholder with a real probe, kept inside a CachedProbe.
    def self.probes
      @probes ||= {
        database: Probes::Database.new,
        storage: CachedProbe.new(Probes::NotConfigured.new, ttl: PROVIDER_PROBE_TTL),
        ocr: CachedProbe.new(Probes::NotConfigured.new, ttl: PROVIDER_PROBE_TTL),
        llm: CachedProbe.new(Probes::NotConfigured.new, ttl: PROVIDER_PROBE_TTL)
      }
    end

    def self.healthy?(probe)
      probe.call ? true : false
    rescue StandardError
      false
    end

    def initialize(probes:)
      @probes = probes
    end

    def call
      statuses = { app: "ok" }.merge(@probes.transform_values { |probe| self.class.healthy?(probe) ? "ok" : "down" })
      { status: overall(statuses), checks: statuses.transform_values { |status| { status: status } } }
    end

    private
      def overall(statuses)
        if statuses[:database] == "down" then "down"
        elsif statuses.value?("down") then "degraded"
        else "ok"
        end
      end
  end
end
