module Eval
  # Scores OCR on a golden directory (images plus labels.json, see eval/README.md): per-field
  # accuracy over all documents and over the hard cases, using Eval::FieldMatch.
  class OcrScorer
    FIELDS = FieldMatch::FIELDS

    # reader: any callable from an image path to a hash of field values (nil for unread fields).
    # The default runs real Tesseract through Ocr::Extractor and Ocr::FieldMapper.
    def initialize(golden_dir:, reader: nil)
      @golden_dir = Pathname(golden_dir)
      @reader = reader || method(:read_with_tesseract)
    end

    def call
      labels = JSON.parse(@golden_dir.join("labels.json").read)
      results = labels.map { |label| score(label) }
      hard = results.select { |result| result[:hard] }

      {
        all: accuracy(results), hard: accuracy(hard),
        counts: { all: results.size, hard: hard.size },
        misses: results.flat_map { |result| result[:misses] }
      }
    end

    private

    def score(label)
      read = read(@golden_dir.join(label["image"]).to_s)
      expected = label["expected"]
      matches = FIELDS.index_with { |field| FieldMatch.match?(field, expected[field.to_s], read[field]) }
      misses = FIELDS.reject { |field| matches[field] }.map do |field|
        { id: label["id"], field: field, expected: expected[field.to_s], read: read[field] }
      end
      { hard: label["hard"] == true, matches: matches, misses: misses }
    end

    # A document the reader can't read counts as a miss on every field.
    def read(path)
      @reader.call(path).to_h
    rescue StandardError
      {}
    end

    def accuracy(results)
      FIELDS.index_with do |field|
        results.empty? ? 0.0 : results.count { |result| result[:matches][field] }.fdiv(results.size)
      end
    end

    def read_with_tesseract(path)
      @extractor ||= Ocr::Extractor.new
      @mapper ||= Ocr::FieldMapper.new
      @mapper.call(@extractor.call(path)).fields.transform_values { |reading| reading&.value }
    end
  end
end
