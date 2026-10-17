# Shared setup for the chat specs: the committed eval sets, the assessment schema, a scripted LLM
# and stubs for the seams other slices own (Consent::Ledger, Scheduling::Booker).
#
#   llm = FakeLlmAdapter.new.respond_with(llm_output("ask-question", reply: "Happy to help."))
#   result = send_chat("What happens next?", llm: llm)
#   result.reply # => "Happy to help."
module ChatHelpers
  INTENTS = %w[provide-details ask-question request-reschedule express-distress out-of-scope].freeze
  HANDLERS = {
    "provide-details" => "Chat::Handlers::ProvideDetails",
    "ask-question" => "Chat::Handlers::AskQuestion",
    "request-reschedule" => "Chat::Handlers::RequestReschedule",
    "express-distress" => "Chat::Handlers::ExpressDistress",
    "out-of-scope" => "Chat::Handlers::OutOfScope"
  }.freeze
  REQUIRED_ASSESSMENT_FIELDS = %w[reason urgency preferred_window distress notes].freeze
  HIGH_STRESS_TRIGGER = "high-stress-intent".freeze
  # The HTTP envelope's action names, which the web reads. Llm::Error uses its own internal names
  # (try_again, continue_manually); the chat API maps them at the boundary.
  WIRE_ERROR_ACTIONS = %w[retry manual_entry].freeze

  EVAL_DIR = Rails.root.join("eval/chat")
  SCHEMA_PATH = Rails.root.join("app/schemas/assessment.json")

  # Day names, clock times and calendar dates, for checking that a reply states no time.
  DATE_OR_TIME = /
    \b(?:mon|tues|wednes|thurs|fri|satur|sun)day\b |
    \b(?:today|tomorrow|tonight|next\s+week)\b |
    \b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b |
    \b\d{1,2}:\d{2}\b |
    \b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?\b |
    \b\d{4}-\d{2}-\d{2}\b |
    \b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b
  /ix

  # Phrases that claim a booking exists or changed.
  BOOKING_CLAIM = /
    you(?:'re|\s+are)\s+(?:all\s+)?(?:booked|confirmed|scheduled|set) |
    (?:appointment|booking)\s+(?:is|has\s+been)\s+(?:confirmed|booked|moved|rescheduled|scheduled) |
    i(?:'ve|\s+have)\s+(?:booked|moved|rescheduled|scheduled)
  /ix

  # Phrases that claim a diagnosis, or promise an outcome, approval or eligibility (R3). Kept
  # separate from Chat::ReplyGuard's own patterns, so a spec can't pass by sharing its blind spots.
  DIAGNOSIS_OR_OUTCOME = /
    \b(?:you|you've|you\s+have|you're|you\s+are)\s+(?:probably\s+|likely\s+|clearly\s+|definitely\s+)?
      (?:have|got|suffering\s+from|dealing\s+with)\s+(?:a\s+|an\s+)?
      (?:depression|anxiety|ptsd|adhd|insomnia|bipolar|ocd|herniated|slipped|torn|sciatica|[a-z]+\s+disorder) |
    \b(?:sounds|looks)\s+like\s+(?:you\s+have\s+)?(?:a\s+|an\s+)?(?:depression|anxiety|ptsd|adhd|insomnia|[a-z]+\s+disorder) |
    \b(?:you'll|you\s+will)\s+(?:definitely\s+|certainly\s+|surely\s+)?(?:be\s+(?:approved|accepted|eligible|covered)|get\s+(?:approved|accepted|in)|qualify) |
    \b(?:you're|you\s+are)\s+(?:definitely\s+|certainly\s+)?(?:eligible|approved|accepted|covered|guaranteed) |
    \byou\s+qualify\b |
    \b(?:this|it|that|therapy|treatment)\s+(?:will|is\s+going\s+to)\s+(?:definitely\s+|certainly\s+)?(?:fix|cure|solve|heal) |
    \bguaranteed\s+to\s+(?:work|help|fix) |
    \bthis\s+is\s+(?:clearly\s+|definitely\s+)?(?:a\s+|an\s+)?(?:depression|anxiety|ptsd|adhd|insomnia|[a-z]+\s+disorder)
  /ix

  # Loads api/eval/chat/<name>.yml. Module methods, so specs can generate examples from the sets.
  def self.eval_set(name)
    YAML.load_file(EVAL_DIR.join("#{name}.yml"))
  end

  def self.adversarial_inputs
    eval_set("adversarial").map do |entry|
      next entry unless entry["repeat"]

      text, length = entry["repeat"].values_at("text", "length")
      entry.merge("message" => (text * ((length / text.length) + 1))[0, length])
    end
  end

  def intent_set
    ChatHelpers.eval_set("intents")
  end

  def scripted_conversations
    ChatHelpers.eval_set("conversations")
  end

  def adversarial_inputs
    ChatHelpers.adversarial_inputs
  end

  def assessment_schema
    JSON.parse(File.read(SCHEMA_PATH))
  end

  def assessment_schemer
    JSONSchemer.schema(assessment_schema)
  end

  def schema_errors(data)
    assessment_schemer.validate(JSON.parse(data.to_json)).map { |error| error["error"] }
  end

  # One structured LLM output in the shape every adapter returns: { intent, assessment_fields, reply }.
  def llm_output(intent, fields: {}, reply: "Thanks, noted.")
    { "intent" => intent, "assessment_fields" => fields, "reply" => reply }
  end

  def fake_llm(*outputs)
    outputs.each_with_object(FakeLlmAdapter.new) { |output, adapter| adapter.respond_with(output) }
  end

  def llm_client_for(adapter)
    Llm::Client.new(primary: adapter)
  end

  # Each message gets a new orchestrator, as each HTTP request would, so state between messages
  # must come from the database.
  def send_chat(message, llm:, user_id: chat_user_id, **options)
    Chat::Orchestrator.new(user_id: user_id, llm_client: llm_client_for(llm)).handle(message: message, **options)
  end

  # Consent::Ledger belongs to the consent slice. Chat only asks whether the user has withdrawn
  # consent or asked for deletion; pass several values to change the answer from call to call.
  def stub_consent(*withdrawn)
    withdrawn = [ false ] if withdrawn.empty?
    ledger = class_double("Consent::Ledger").as_stubbed_const
    allow(ledger).to receive(:withdrawn?).and_return(*withdrawn)
    ledger
  end

  # Scheduling::Booker belongs to the scheduling slice. Its result exposes success?, outcome and
  # to_h (plain data, ISO-8601 UTC times); reply templates may use only those.
  def stub_booker(result)
    booker = instance_double("Scheduling::Booker", reschedule: result, cancel: result)
    booker_class = class_double("Scheduling::Booker", new: booker).as_stubbed_const
    [ booker_class, booker ]
  end

  def booker_result(outcome:, success:, slot: nil, previous_slot: nil, booking_id: SecureRandom.uuid)
    double("Scheduling::Booker result", success?: success, outcome: outcome,
      to_h: { outcome: outcome.to_s, booking_id: booking_id, slot: slot, previous_slot: previous_slot })
  end

  # The chat's structured choices (R36): the open slots offered for a reschedule, as the web
  # sends them back, and the cancel confirmation.
  def slot_choice(booking, slot)
    { "type" => "slot", "booking_id" => booking.id, "slot" => slot.summary.stringify_keys }
  end

  def confirm_cancel_choice(booking)
    { "type" => "confirm_cancel", "booking_id" => booking.id }
  end

  def saved_assessments(user_id)
    Assessment.where(user_id: user_id).map { |record| JSON.parse(record.data.to_json) }
  end

  def user_turns(adapter)
    adapter.payloads.flat_map { |payload| payload.messages.select { |message| message[:role] == "user" } }
  end
end

RSpec.configure do |config|
  config.include ChatHelpers
  config.define_derived_metadata(file_path: %r{spec/(services/chat|requests/chat)}) { |meta| meta[:chat] = true }
  config.before(chat: true) { stub_consent }
end
