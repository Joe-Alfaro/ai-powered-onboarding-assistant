module Ocr
  # The fields Ocr::FieldMapper read. Each field is nil or an Ocr::Reading. When manual_entry? is
  # true every field is nil and reason says why (:no_text, :low_confidence, :ocr_error, :no_fields).
  Result = Data.define(:fields, :reason) do
    def self.manual_entry(reason)
      new(fields: FieldMapper::FIELDS.index_with(nil), reason: reason)
    end

    def manual_entry?
      !reason.nil?
    end
  end
end
