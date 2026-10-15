module Llm
  # Builds the only payload that can leave for an LLM (R20). It replaces the user's known identity
  # values with placeholders, keeps only the assessment fields the LLM is asked to fill, and
  # refuses anything that is not plain text. docs/data-to-llm.md lists what gets through.
  class PayloadBuilder
    class DisallowedContent < ArgumentError; end

    ROLES = %w[user assistant].freeze
    NAME = "[NAME]".freeze
    DATE_OF_BIRTH = "[DATE_OF_BIRTH]".freeze
    ADDRESS = "[ADDRESS]".freeze
    IMAGE_DATA_URI = %r{data:image/}i
    # Control characters other than tab, newline and carriage return only appear in binary data.
    CONTROL_CHARACTERS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
    ORDINAL = "(?:st|nd|rd|th)?".freeze

    # identity: the user's known full_name, date_of_birth (Date or ISO string) and address; any
    # may be nil while onboarding is still collecting them.
    def initialize(identity:)
      @replacements = build_replacements(identity.to_h.symbolize_keys)
    end

    def build(system:, turns:, assessment_draft:, response_schema:)
      messages = turns.map { |turn| build_message(turn.to_h.symbolize_keys) }
      draft = allowed_draft(assessment_draft.to_h.stringify_keys, response_schema)

      Payload.send(:new, system: system_with_draft(text(system), draft), messages: messages,
                         response_schema: response_schema)
    end

    private

    attr_reader :replacements

    def build_message(turn)
      role = turn[:role].to_s
      raise ArgumentError, "turn role must be one of #{ROLES.join(', ')}" unless role.in?(ROLES)

      { role: role, content: redact(text(turn[:content])) }
    end

    def system_with_draft(system, draft)
      return system if draft.empty?

      "#{system}\n\nCurrent assessment draft (JSON): #{draft.to_json}"
    end

    # Keeps only the draft keys the response schema declares under assessment_fields, so stray
    # fields (an email, an internal ID) can't ride along.
    def allowed_draft(draft, response_schema)
      declared = response_schema.deep_stringify_keys.dig("properties", "assessment_fields", "properties")&.keys || []
      draft.slice(*declared).transform_values { |value| draft_value(value) }
    end

    def draft_value(value)
      case value
      when String then redact(text(value))
      when Array then value.map { |item| draft_value(item) }
      when Numeric, true, false, nil then value
      else raise DisallowedContent, "assessment draft values must be text, numbers or booleans"
      end
    end

    def text(value)
      raise DisallowedContent, "LLM content must be plain text, got #{value.class}" unless value.is_a?(String)

      utf8 = value.encoding == Encoding::UTF_8 ? value : value.dup.force_encoding(Encoding::UTF_8)
      raise DisallowedContent, "LLM content must be valid UTF-8 text" unless utf8.valid_encoding?
      raise DisallowedContent, "LLM content must not contain binary data" if utf8.match?(CONTROL_CHARACTERS)
      raise DisallowedContent, "LLM content must not contain an image" if utf8.match?(IMAGE_DATA_URI)

      utf8
    end

    def redact(content)
      replacements.reduce(content) { |redacted, (pattern, placeholder)| redacted.gsub(pattern, placeholder) }
    end

    # Ordered [pattern, placeholder] pairs. Whole values go before their parts, so a full name
    # becomes one [NAME] rather than one per part.
    def build_replacements(identity)
      address_patterns(identity[:address]).map { |pattern| [ pattern, ADDRESS ] } +
        date_of_birth_patterns(identity[:date_of_birth]).map { |pattern| [ pattern, DATE_OF_BIRTH ] } +
        name_patterns(identity[:full_name]).map { |pattern| [ pattern, NAME ] }
    end

    def address_patterns(address)
      return [] if address.blank?

      street = address.split(",").first.strip
      [ address, (street if street != address.strip && street.length >= 5) ].compact.map { |value| phrase(value) }
    end

    def name_patterns(full_name)
      return [] if full_name.blank?

      parts = full_name.split(/\s+/).flat_map { |word| [ word, *word.split("-") ] }
      ([ full_name ] + parts.select { |part| part.length >= 2 }.sort_by { |part| -part.length })
        .uniq(&:downcase).map { |value| phrase(value) }
    end

    # A case-insensitive whole-word match that tolerates any run of spaces and commas between words.
    def phrase(value)
      words = value.strip.split(/[\s,]+/).map { |word| Regexp.escape(word) }
      /(?<![[:alnum:]])#{words.join('[\s,]+')}(?![[:alnum:]])/i
    end

    def date_of_birth_patterns(date_of_birth)
      return [] if date_of_birth.blank?

      date = date_of_birth.is_a?(Date) ? date_of_birth : Date.iso8601(date_of_birth.to_s)
      [ /(?<!\d)(?:#{date_forms(date).join('|')})(?!\d)/i ]
    rescue Date::Error
      [ phrase(date_of_birth.to_s) ]
    end

    # ISO, US and day-first numeric, and written-month forms of one date.
    def date_forms(date)
      year = date.year
      month = "0?#{date.month}"
      day = "0?#{date.day}#{ORDINAL}"
      month_name = "(?:#{Date::MONTHNAMES[date.month]}|#{Date::ABBR_MONTHNAMES[date.month]}\\.?)"
      separator = "[-/.]"

      [
        "#{year}#{separator}#{month}#{separator}0?#{date.day}",
        "#{month}#{separator}0?#{date.day}#{separator}#{year}",
        "0?#{date.day}#{separator}#{month}#{separator}#{year}",
        "#{month_name}\\s+#{day},?\\s+#{year}",
        "#{day}\\s+(?:of\\s+)?#{month_name},?\\s+#{year}"
      ]
    end
  end
end
