module OcrHelpers
  # Builds an Ocr::Extraction from lines of [text, confidence] pairs, one pair per word, so
  # FieldMapper specs can control exactly what Tesseract "read" and how sure it was.
  #
  #   build_extraction([["NAME", 95], ["JANE", 95]], [["DOB", 95], ["03/14/1985", 90]])
  def build_extraction(*lines, error: nil)
    words = lines.map do |line|
      line.map { |text, confidence| Ocr::Word.new(text: text, confidence: confidence) }
    end
    Ocr::Extraction.new(lines: words, error: error)
  end

  # Splits each string into words that all share one confidence.
  def lines_at(confidence, *strings)
    strings.map { |string| string.split.map { |word| [ word, confidence ] } }
  end

  def ocr_fixture(name)
    Rails.root.join("spec/fixtures/files/ocr", name).to_s
  end
end

RSpec.configure do |config|
  config.include OcrHelpers
end
