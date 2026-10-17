module Chat
  # No made-up commitments (R3): LLM reply text that states a day, date, clock time or booking is
  # swapped for the handler's template. Times and booking states reach the user only from handler
  # results, which the templates never put in the text. Text that diagnoses the user or promises an
  # outcome, approval or eligibility is swapped too, with a line saying the chatbot can't do either.
  module ReplyGuard
    DATE_OR_TIME = /
      \b(?:mon|tues|wednes|thurs|fri|satur|sun)day\b |
      \b(?:today|tomorrow|tonight|next\s+(?:week|month))\b |
      \b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?|o'clock)(?![a-z]) |
      \b\d{1,2}[:.]\d{2}\b |
      \b(?:noon|midnight)\b |
      \b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?\b |
      \b\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b |
      \b\d{4}-\d{2}-\d{2}\b |
      \b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b
    /ix

    BOOKING_CLAIM = /
      \byou(?:'re|\s+are)\s+(?:all\s+)?(?:booked|confirmed|scheduled|set\s+for|rescheduled) |
      \b(?:appointment|booking|slot)\s+(?:is|has\s+been|was)\s+(?:confirmed|booked|moved|rescheduled|scheduled|changed|cancell?ed) |
      \bi(?:'ve|\s+have)?\s+(?:booked|moved|rescheduled|scheduled|confirmed|cancell?ed)\b |
      \b(?:booked|scheduled|rescheduled)\s+(?:you|it)\b
    /ix

    CONDITION = /
      depress(?:ion|ive)|anxiety|panic\s+attacks?|ptsd|adhd|insomnia|bipolar|ocd|autism|burnout|
      schizophreni[a-z]*|herniated|slipped\s+disc|bulging\s+disc|torn\s+[a-z]+|sciatica|arthritis|
      fracture|sprain|concussion|[a-z]+\s+(?:disorder|syndrome|disease)|[a-z]+itis
    /ix

    DIAGNOSIS = /
      \byou(?:'ve|'re|\s+are)?\s+(?:probably\s+|likely\s+|clearly\s+|definitely\s+|might\s+|may\s+)?
        (?:have|has|got|suffer(?:ing)?\s+from|dealing\s+with|showing\s+signs\s+of)\s+
        (?:a\s+|an\s+|some\s+)?(?:mild\s+|severe\s+|clinical\s+|chronic\s+)?(?:#{CONDITION}) |
      \b(?:sounds|looks|seems)\s+like\s+(?:you\s+(?:have|are\s+experiencing)\s+)?(?:a\s+|an\s+)?(?:#{CONDITION}) |
      \b(?:this|that|it)\s+(?:is|sounds\s+like|looks\s+like)\s+(?:clearly\s+|definitely\s+|probably\s+)?
        (?:a\s+|an\s+)?(?:#{CONDITION})
    /ix

    OUTCOME_PROMISE = /
      \byou(?:'ll|\s+will)\s+(?:definitely\s+|certainly\s+|surely\s+|absolutely\s+)?
        (?:be\s+(?:approved|accepted|eligible|covered|cured)|get\s+(?:approved|accepted|in|covered)|qualify) |
      \byou(?:'re|\s+are)\s+(?:definitely\s+|certainly\s+|already\s+)?(?:eligible|approved|accepted|covered|qualified) |
      \byou\s+(?:definitely\s+|certainly\s+)?qualify\b |
      \b(?:this|it|that|therapy|treatment|we)(?:'ll|\s+will|\s+is\s+going\s+to)\s+(?:definitely\s+|certainly\s+)?
        (?:fix|cure|solve|heal) |
      \bguaranteed\s+to\b | \bi\s+guarantee\b
    /ix

    NO_DIAGNOSIS_OR_OUTCOME = "I can't diagnose anything or promise an outcome; a clinician will go over " \
                              "that with you.".freeze

    module_function

    # llm_reply: the LLM's text, or nil when the handler doesn't use it. template: the handler's
    # own reply, used whenever the LLM's can't be trusted.
    def call(llm_reply:, template:)
      return template if llm_reply.blank?
      return "#{NO_DIAGNOSIS_OR_OUTCOME} #{template}" if diagnosis_or_outcome?(llm_reply)
      return template if unbacked_claim?(llm_reply)

      llm_reply
    end

    def unbacked_claim?(text)
      text = normalize(text)
      text.match?(DATE_OR_TIME) || text.match?(BOOKING_CLAIM) || diagnosis_or_outcome?(text)
    end

    def diagnosis_or_outcome?(text)
      text = normalize(text)
      text.match?(DIAGNOSIS) || text.match?(OUTCOME_PROMISE)
    end

    # Typographic apostrophes, which LLMs often write, read as plain ones.
    def normalize(text)
      text.tr("\u2018\u2019", "''")
    end
  end
end
