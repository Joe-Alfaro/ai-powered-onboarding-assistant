module Chat
  # No made-up commitments (R3): LLM reply text that states a day, date, clock time or booking is
  # swapped for the handler's template. Times and booking states reach the user only from handler
  # results, which the templates never put in the text.
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

    module_function

    # llm_reply: the LLM's text, or nil when the handler doesn't use it. template: the handler's
    # own reply, used whenever the LLM's can't be trusted.
    def call(llm_reply:, template:)
      return template if llm_reply.blank? || unbacked_claim?(llm_reply)

      llm_reply
    end

    def unbacked_claim?(text)
      text.match?(DATE_OR_TIME) || text.match?(BOOKING_CLAIM)
    end
  end
end
