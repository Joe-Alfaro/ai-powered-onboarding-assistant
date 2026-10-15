module Health
  module Probes
    # Placeholder for a dependency whose real probe isn't built yet. It reports down rather than
    # claiming a dependency is healthy without checking it.
    class NotConfigured
      def call
        false
      end
    end
  end
end
