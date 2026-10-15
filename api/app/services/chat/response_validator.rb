module Chat
  # Checks one LLM answer against the intent list and the assessment schema (R2). A valid answer
  # becomes an Output holding only fields the schema defines; an invalid one yields the reasons,
  # which go back to the LLM on the retry. The reasons name fields, never values.
  module ResponseValidator
    Output = Data.define(:intent, :fields, :reply)

    module_function

    # Returns [output, nil] or [nil, errors].
    def call(data)
      data = {} unless data.is_a?(Hash)
      errors = []
      errors << "intent must be one of #{Prompt::INTENTS.join(', ')}" unless data["intent"].in?(Prompt::INTENTS)
      errors << "reply must be a string" unless data["reply"].is_a?(String)
      fields = data["assessment_fields"]

      if fields.is_a?(Hash)
        fields = provided(fields)
        errors.concat(AssessmentSchema.partial_errors(fields).map { |pointer| "assessment_fields#{pointer} is not valid" })
      else
        errors << "assessment_fields must be an object"
      end

      errors.empty? ? [ Output.new(intent: data["intent"], fields: fields, reply: data["reply"]), nil ] : [ nil, errors ]
    end

    # Keeps the schema's fields and drops the rest. Null and empty values count as not provided,
    # since providers with strict schemas often send every property.
    def provided(fields)
      fields.slice(*AssessmentSchema.field_names).reject { |_, value| value.nil? || value == "" }
    end
  end
end
