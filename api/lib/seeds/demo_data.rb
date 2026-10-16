module Seeds
  # The data bin/rails db:seed loads (R32): open slots over the next two weeks, the demo users in
  # Supabase Auth, and a check that the OCR golden set is in place. Safe to run again: existing
  # slots and users are left as they are, and the demo credentials are printed on every run.
  class DemoData
    # The seed can't run as asked, for example because the golden set is missing.
    class Error < StandardError; end

    # Fixed, so the README can list them. Reserved domains, so no mail ever leaves.
    DEMO_PASSWORD = "demo-onboarding-2026".freeze
    DEMO_EMAILS = %w[demo@example.com demo2@example.com].freeze

    SLOT_DAYS = 14
    SLOT_HOURS_UTC = [ 14, 15, 16, 17, 18, 19 ].freeze
    SLOT_LENGTH = 30.minutes

    def self.default
      golden_dir = Rails.root.join(ENV["GOLDEN_DIR"].presence || "eval/golden")
      new(auth: Auth::AdminClient.default, golden_dir: golden_dir)
    end

    def initialize(auth:, golden_dir:, out: $stdout, now: Time.current)
      @auth = auth
      @golden_dir = Pathname(golden_dir)
      @out = out
      @now = now
    end

    def call
      golden = golden_set_size
      slots = seed_slots
      @out.puts "Slots: #{slots} open slots over the next #{SLOT_DAYS} days"
      @out.puts "Golden set: #{golden} labeled documents in #{@golden_dir}"
      seed_users
    end

    private
      # Checked first, so a missing golden set stops the seed before it writes anything.
      def golden_set_size
        labels_file = @golden_dir.join("labels.json")
        raise Error, "Golden set not found: #{labels_file} is missing" unless labels_file.file?

        labels = JSON.parse(labels_file.read)
        missing = labels.map { |label| label["image"].to_s }.reject { |image| @golden_dir.join(image).file? }
        raise Error, "Golden set is incomplete: missing #{missing.join(', ')}" if missing.any?

        labels.size
      end

      # Weekdays from tomorrow (UTC), at fixed UTC hours.
      def seed_slots
        first_day = @now.utc.to_date + 1
        days = (first_day...(first_day + SLOT_DAYS)).reject { |day| day.saturday? || day.sunday? }
        days.product(SLOT_HOURS_UTC).each do |day, hour|
          starts_at = Time.utc(day.year, day.month, day.day, hour)
          Slot.find_or_create_by!(starts_at: starts_at, ends_at: starts_at + SLOT_LENGTH)
        end
        Slot.open.count
      end

      def seed_users
        @out.puts "Demo users (sign in at the web app):"
        DEMO_EMAILS.each do |email|
          state = @auth.create_user(email: email, password: DEMO_PASSWORD)
          @out.puts "  #{email} / #{DEMO_PASSWORD}#{' (already existed)' if state == :exists}"
        end
      end
  end
end
