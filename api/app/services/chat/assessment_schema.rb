module Chat
  # The committed assessment schema (app/schemas/assessment.json) and the checks built on it (R2).
  module AssessmentSchema
    PATH = Rails.root.join("app/schemas/assessment.json")
    # Collected from the LLM before an assessment can be saved; distress and notes have defaults.
    COLLECTED_FIELDS = %w[reason urgency preferred_window].freeze
    DEFAULTS = { "distress" => false, "notes" => "" }.freeze
    # A bracketed token such as <UNKNOWN>, <reason> or [NAME]: an LLM's stand-in for a value it
    # doesn't have, or an identity placeholder from Llm::PayloadBuilder echoed back.
    PLACEHOLDER_TOKEN = /(?i:<\s*[a-z][a-z0-9_ ]*\s*>)|\[\s*[A-Z][A-Z0-9_ ]*\s*\]/
    # Whole values that stand for "no answer" rather than an answer.
    SENTINELS = [
      "unknown", "n/a", "na", "none", "none provided", "null", "nil", "undefined", "tbd", "not provided",
      "not specified", "not stated", "not given", "not mentioned", "not applicable", "unspecified"
    ].freeze

    module_function

    def schema
      @schema ||= JSON.parse(File.read(PATH)).freeze
    end

    def version
      schema.fetch("version")
    end

    def properties
      schema.fetch("properties")
    end

    def field_names
      properties.keys
    end

    def valid?(data)
      data.is_a?(Hash) && full_schemer.valid?(JSON.parse(data.to_json)) && data.values.none? { |value| placeholder?(value) }
    end

    # True for text that stands in for a missing value (R2): a placeholder token, a sentinel such as
    # "unknown" or "N/A", or nothing but punctuation. Such values count as not provided.
    def placeholder?(value)
      return false unless value.is_a?(String)
      return true if value.match?(PLACEHOLDER_TOKEN)

      bare = value.downcase.strip.gsub(/\A[[:punct:]\s]+|[[:punct:]\s]+\z/, "")
      bare.empty? ? value.strip.present? : bare.in?(SENTINELS)
    end

    # The fields that hold a real value: nil, empty and placeholder values count as not provided.
    def provided(fields)
      fields.reject { |_, value| value.nil? || value == "" || placeholder?(value) }
    end

    # Error locations for a set of fields that may be incomplete, for example one LLM answer.
    # Each property is checked against its own schema; unknown properties are rejected.
    def partial_errors(fields)
      partial_schemer.validate(JSON.parse(fields.to_json)).map { |error| error["data_pointer"].presence || "/" }.uniq
    end

    def full_schemer
      @full_schemer ||= JSONSchemer.schema(schema)
    end

    def partial_schemer
      @partial_schemer ||= JSONSchemer.schema(schema.except("required", "$id"))
    end
  end
end
