module Ocr
  # What Ocr::Extractor read from an image: lines of Ocr::Words, or an error when OCR failed.
  class Extraction
    attr_reader :lines, :error

    def self.failure(error)
      new(lines: [], error: error)
    end

    def initialize(lines: [], error: nil)
      @lines = lines.map { |line| line.reject { |word| word.text.to_s.strip.empty? } }.reject(&:empty?)
      @error = error
    end

    def words
      lines.flatten
    end

    def text
      lines.map { |line| line.map(&:text).join(" ") }.join("\n")
    end

    # Mean word confidence, or 0 when nothing was read.
    def confidence
      return 0.0 if words.empty?

      words.sum(&:confidence).fdiv(words.size)
    end

    def failed?
      !error.nil?
    end

    def empty?
      words.empty?
    end
  end
end
