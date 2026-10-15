module Chat
  # The committed assessment schema (app/schemas/assessment.json) and the checks built on it (R2).
  module AssessmentSchema
    PATH = Rails.root.join("app/schemas/assessment.json")
    # Collected from the LLM before an assessment can be saved; distress and notes have defaults.
    COLLECTED_FIELDS = %w[reason urgency preferred_window].freeze
    DEFAULTS = { "distress" => false, "notes" => "" }.freeze

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
      data.is_a?(Hash) && full_schemer.valid?(JSON.parse(data.to_json))
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
