module Chat
  module Handlers
    # One handler per intent, built with a Context; #call returns an Outcome.
    class Base
      NEXT_QUESTIONS = {
        "reason" => "Thanks. What's the main reason you're looking for support?",
        "urgency" => "Thanks. How urgent does this feel for you: low, medium or high?",
        "preferred_window" => "Thanks. When do appointments generally suit you, for example weekday " \
                              "mornings or evenings?"
      }.freeze
      ALL_COLLECTED = "Thanks, I have what I need. Here's a summary of what you told me.".freeze

      def initialize(context)
        @context = context
      end

      private

      attr_reader :context

      def next_question(draft)
        missing = AssessmentSchema::COLLECTED_FIELDS.find { |field| draft[field].blank? }
        NEXT_QUESTIONS.fetch(missing, ALL_COLLECTED)
      end
    end
  end
end
