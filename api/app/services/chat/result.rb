module Chat
  # What one chat message produced. `actions` uses Llm::Error's internal names (try_again,
  # continue_manually); the HTTP layer maps them to the wire vocabulary. `assessment` is the saved
  # record, set only on the message that saved it; `scheduling` is Scheduling::Booker's result;
  # `choices` are the structured choices the user can send back (R36).
  Result = Data.define(:reply, :intent, :trigger, :actions, :assessment, :scheduling, :choices) do
    def initialize(reply:, intent: nil, trigger: nil, actions: [], assessment: nil, scheduling: nil, choices: [])
      super
    end
  end
end
