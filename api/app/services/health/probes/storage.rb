module Health
  module Probes
    # Looks up the uploads bucket in Supabase Storage with the service role key. Up only when the
    # bucket exists and Storage answers in time.
    class Storage
      def initialize(timeout:)
        @timeout = timeout
      end

      # Reads the environment on each call, so a config change needs no rebuilt registry.
      def call
        ::Storage::Client.default(timeout: @timeout).check_bucket
      end
    end
  end
end
