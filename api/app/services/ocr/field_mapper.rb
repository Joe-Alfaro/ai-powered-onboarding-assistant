module Ocr
  # Maps an Ocr::Extraction to name, date of birth and address using label anchors. A field is
  # only taken from the value after its own label; anything it can't read is nil, never a guess.
  # No network calls: nothing here leaves the process.
  class FieldMapper
    FIELDS = %i[full_name date_of_birth address].freeze
    DEFAULT_THRESHOLD = 60

    # Label phrases, matched as whole words at the start of a line (case-insensitive).
    LABELS = {
      full_name: [ %w[full name], %w[name] ],
      date_of_birth: [ %w[date of birth], %w[birth date], %w[dob] ],
      address: [ %w[address], %w[addr] ]
    }.freeze

    # Labels of fields we don't extract. They end an address and are never taken as a value.
    OTHER_LABELS = [
      %w[iss], %w[issued], %w[exp], %w[expires], %w[sex], %w[hgt], %w[wgt], %w[eyes], %w[hair],
      %w[class], %w[id no], %w[dl], %w[restr]
    ].freeze

    ALL_LABELS = (LABELS.values.flatten(1) + OTHER_LABELS).sort_by { |label| -label.size }.freeze
    MAX_ADDRESS_LINES = 3
    MAX_JUNK_TOKENS = 2

    MONTHS = Date::MONTHNAMES.compact.each_with_index.flat_map do |name, index|
      [ [ name.upcase, index + 1 ], [ name[0, 3].upcase, index + 1 ] ]
    end.to_h.freeze

    def initialize(threshold: ENV.fetch("OCR_CONFIDENCE_THRESHOLD", DEFAULT_THRESHOLD))
      @threshold = Float(threshold)
    end

    def call(extraction)
      return Result.manual_entry(:ocr_error) if extraction.failed?
      return Result.manual_entry(:no_text) if extraction.empty?
      return Result.manual_entry(:low_confidence) if extraction.confidence < @threshold

      lines = extraction.lines.map { |line| line.map { |word| Token.new(word) }.reject { |token| token.key.empty? } }
      fields = {
        full_name: read_name(lines),
        date_of_birth: read_date_of_birth(lines),
        address: read_address(lines)
      }
      return Result.manual_entry(:no_fields) if fields.values.all?(&:nil?)

      Result.new(fields: fields, reason: nil)
    end

    private

    # A word and the form it's compared to labels in: letters and digits only, lowercased. In a
    # word that has a letter, the digits OCR most often reads in place of letters are turned back
    # (so "1D" is the ID label); all-digit words are left alone. Only labels are matched this way;
    # values are always kept exactly as read.
    Token = Data.define(:word, :key) do
      def initialize(word:)
        key = word.text.upcase.gsub(/[^A-Z0-9]/, "")
        key = key.tr("0158", "OISB") if key.match?(/[A-Z]/)
        super(word: word, key: key.downcase)
      end
    end

    def read_name(lines)
      words = value_after(lines, :full_name)
      return nil if words.nil?

      text = clean(words)
      return nil unless text.match?(/[[:alpha:]]{2}/) && !text.match?(/\d/)

      reading(text, words)
    end

    def read_date_of_birth(lines)
      words = value_after(lines, :date_of_birth)
      return nil if words.nil?

      date = parse_date(clean(words))
      return nil if date.nil? || date > Date.current || date.year < 1900

      reading(date.iso8601, words)
    end

    def read_address(lines)
      index, words = find_label(lines, :address)
      return nil if index.nil?

      parts = [ value_words(words) ]
      lines[(index + 1)..].first(MAX_ADDRESS_LINES).each do |line|
        break if label_at(line.drop(junk_before_label(line)))
        break if line.empty?

        parts << value_words(line)
      end
      parts = parts.reject(&:empty?)
      return nil if parts.empty?

      text = parts.map { |part| clean(part).delete_suffix(",") }.join(", ")
      reading(text, parts.flatten)
    end

    # The words after a field's label on the same line, up to the next inline label.
    def value_after(lines, field)
      _index, words = find_label(lines, field)
      return nil if words.nil?

      value = value_words(words)
      value.empty? ? nil : value
    end

    # The first line that starts with one of the field's labels, and the tokens after the label.
    def find_label(lines, field)
      lines.each_with_index do |line, index|
        line = line.drop(junk_before_label(line))
        label = label_at(line)
        return [ index, line.drop(label.size) ] if label && LABELS[field].include?(label)
      end
      nil
    end

    # How many low-confidence tokens come before a label at the start of the line. Borders and
    # photo edges often read as a stray low-confidence character in front of a label.
    def junk_before_label(tokens)
      (0..MAX_JUNK_TOKENS).find do |count|
        tokens.first(count).all? { |token| token.word.confidence < @threshold } && label_at(tokens.drop(count))
      end || 0
    end

    def label_at(tokens)
      ALL_LABELS.find { |label| tokens.first(label.size).map(&:key) == label }
    end

    # Stops at the next label on the same line.
    def value_words(tokens)
      stop = (1...tokens.size).find { |position| label_at(tokens.drop(position)) }
      tokens.first(stop || tokens.size).map(&:word)
    end

    def clean(words)
      words.map(&:text).join(" ").gsub(/\A[\s:;.,|-]+|[\s:;|-]+\z/, "").squeeze(" ")
    end

    def reading(value, words)
      confidence = words.sum(&:confidence).fdiv(words.size).round(1)
      Reading.new(value: value, confidence: confidence, level: confidence >= @threshold ? :high : :low)
    end

    def parse_date(text)
      year, month, day =
        case text.upcase.delete(",").squeeze(" ")
        when /\A(\d{4})-(\d{2})-(\d{2})\z/ then [ $1, $2, $3 ].map(&:to_i)
        when %r{\A(\d{1,2})([/.-])(\d{1,2})\2(\d{4})\z} then [ $4.to_i, $1.to_i, $3.to_i ]
        when /\A(\d{1,2}) ([A-Z]+) (\d{4})\z/ then [ $3.to_i, MONTHS[$2], $1.to_i ]
        when /\A([A-Z]+) (\d{1,2}) (\d{4})\z/ then [ $3.to_i, MONTHS[$1], $2.to_i ]
        end
      return nil if month.nil? || !Date.valid_date?(year, month, day)

      Date.new(year, month, day)
    end
  end
end
