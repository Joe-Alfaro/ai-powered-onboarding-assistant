module Chat
  # Handles one chat message (ARCHITECTURE.md, Chatbot design): one LLM call for the intent,
  # assessment fields and reply, validated against the intent list and the assessment schema and
  # retried once with the reasons; then the intent's handler, the reply guard, and saving the
  # turn, the draft and, once complete, the assessment. Consent is checked before every LLM call
  # (R13). LLM failures other than an unreadable answer propagate as Llm::Error.
  class Orchestrator
    HANDLERS = {
      "provide-details" => Handlers::ProvideDetails,
      "ask-question" => Handlers::AskQuestion,
      "request-reschedule" => Handlers::RequestReschedule,
      "express-distress" => Handlers::ExpressDistress,
      "out-of-scope" => Handlers::OutOfScope
    }.freeze
    LLM_ATTEMPTS = 2
    # Longer messages are cut before they are stored or sent, which bounds cost and latency (R3).
    MAX_MESSAGE_LENGTH = 4_000
    # Earlier messages sent with each call, as user and assistant pairs.
    RECENT_MESSAGES = 10
    FALLBACK_ACTIONS = %w[continue_manually].freeze
    EMPTY_MESSAGE_REPLY = "It looks like that message was empty. Tell me a little about what brings " \
                          "you here, or ask me anything about getting started.".freeze
    # Control characters other than tab, newline and carriage return; Llm::PayloadBuilder refuses them.
    CONTROL_CHARACTERS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

    def initialize(user_id:, llm_client:)
      @user_id = user_id
      @llm_client = llm_client
    end

    def handle(message:, booking_id: nil, slot_id: nil)
      text = clean(message)
      return Result.new(reply: EMPTY_MESSAGE_REPLY) if text.blank?

      conversation = Conversation.for_user(user_id)
      output = classify(conversation, text)
      return respond_with_fallback(conversation, text) unless output

      context = Handlers::Context.new(user_id: user_id, draft: conversation.draft, fields: output.fields,
                                      llm_reply: output.reply, booking_id: booking_id, slot_id: slot_id)
      outcome = HANDLERS.fetch(output.intent).new(context).call
      reply = ReplyGuard.call(llm_reply: outcome.llm_reply, template: outcome.template)
      assessment = record(conversation, text, reply, output.intent, outcome.draft)

      Result.new(reply: reply, intent: output.intent, trigger: outcome.trigger, assessment: assessment,
                 scheduling: outcome.scheduling)
    end

    private

    attr_reader :user_id, :llm_client

    def clean(message)
      return "" unless message.is_a?(String)

      message.dup.force_encoding(Encoding::UTF_8).scrub("").gsub(CONTROL_CHARACTERS, "").strip[0, MAX_MESSAGE_LENGTH]
    end

    # The validated answer, or nil after two invalid ones.
    def classify(conversation, text)
      errors = nil
      LLM_ATTEMPTS.times do
        output, errors = attempt(conversation, text, errors)
        return output if output
      end
      nil
    rescue Llm::PayloadBuilder::DisallowedContent
      nil
    end

    def attempt(conversation, text, retry_errors)
      raise ConsentWithdrawn if Consent::Ledger.withdrawn?(user_id)

      ResponseValidator.call(llm_client.complete(payload(conversation, text, retry_errors)).data)
    rescue Llm::InvalidResponseError
      [ nil, [ "the answer did not follow the response schema" ] ]
    end

    def payload(conversation, text, retry_errors)
      turns = conversation.recent_messages(RECENT_MESSAGES).map { |message| { role: message.role, content: message.content } }
      Llm::PayloadBuilder.new(identity: confirmed_identity).build(
        system: Prompt.system(retry_errors: retry_errors),
        turns: turns + [ { role: "user", content: text } ],
        assessment_draft: conversation.draft,
        response_schema: Prompt.response_schema
      )
    end

    # The identity the user confirmed, from OCR or typed in, so the builder can replace it with
    # placeholders everywhere in the payload (R20). Empty until they confirm.
    def confirmed_identity
      @confirmed_identity ||= Onboarding.find_by(user_id: user_id)&.then do |onboarding|
        onboarding.identity_source? ? onboarding.slice(*Onboarding::IDENTITY_FIELDS) : {}
      end || {}
    end

    def respond_with_fallback(conversation, text)
      reply = Handlers::OutOfScope::REPLY
      record(conversation, text, reply, "out-of-scope", conversation.draft)
      Result.new(reply: reply, intent: "out-of-scope", actions: FALLBACK_ACTIONS)
    end

    # Saves the turn and the draft, and the assessment when the draft completes or changes it.
    # Returns the saved assessment data, or nil when none was saved.
    def record(conversation, text, reply, intent, draft)
      ActiveRecord::Base.transaction do
        conversation.update!(assessment_draft: draft)
        # Explicit, distinct timestamps keep the pair in order when read back.
        now = Time.current
        conversation.messages.create!(role: "user", content: text, intent: intent, created_at: now)
        conversation.messages.create!(role: "assistant", content: reply, created_at: now + 0.001)
        save_assessment(draft)
      end
    end

    def save_assessment(draft)
      return unless AssessmentSchema::COLLECTED_FIELDS.all? { |field| draft[field].present? }

      data = AssessmentSchema::DEFAULTS.merge(draft).slice(*AssessmentSchema.field_names)
      assessment = Assessment.find_or_initialize_by(user_id: user_id)
      assessment.assign_attributes(data: data, schema_version: AssessmentSchema.version)
      return unless assessment.changed?

      assessment.save!
      assessment.data
    end
  end
end
