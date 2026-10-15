module Eval
  # Field-level match for the OCR golden set. Implements exactly the rules in eval/README.md.
  module FieldMatch
    FIELDS = %i[full_name date_of_birth address].freeze

    ADDRESS_ABBREVIATIONS = {
      "street" => "st", "avenue" => "ave", "road" => "rd", "boulevard" => "blvd",
      "drive" => "dr", "lane" => "ln", "court" => "ct", "place" => "pl",
      "apartment" => "apt", "suite" => "ste", "north" => "n", "south" => "s",
      "east" => "e", "west" => "w"
    }.freeze

    MONTHS = Date::MONTHNAMES.compact.each_with_index.flat_map do |name, index|
      [ [ name.downcase, index + 1 ], [ name[0, 3].downcase, index + 1 ] ]
    end.to_h.freeze

    module_function

    def match?(field, expected, read)
      field = field.to_sym
      raise ArgumentError, "unknown field #{field.inspect}" unless FIELDS.include?(field)
      return false if expected.nil? || read.nil?

      if field == :date_of_birth
        expected_date = parse_date(expected)
        !expected_date.nil? && expected_date == parse_date(read)
      else
        normalize(field, expected) == normalize(field, read)
      end
    end

    def normalize(field, value)
      text = basic(value)
      case field.to_sym
      when :full_name
        text.delete(".,")
      when :address
        squish(text.delete(".").tr(",", " ")).split(" ").map { |word| ADDRESS_ABBREVIATIONS.fetch(word, word) }.join(" ")
      else
        text
      end
    end

    # Parses the date formats the README accepts. Returns nil for anything else.
    def parse_date(value)
      text = basic(value)
      year, month, day =
        case text
        when /\A(\d{4})-(\d{2})-(\d{2})\z/
          [ $1, $2, $3 ].map(&:to_i)
        when %r{\A(\d{1,2})([/-])(\d{1,2})\2(\d{4})\z}
          [ $4.to_i, $1.to_i, $3.to_i ]
        when /\A(\d{1,2}),? ([a-z]+) (\d{4})\z/
          [ $3.to_i, MONTHS[$2], $1.to_i ]
        when /\A([a-z]+) (\d{1,2}),? (\d{4})\z/
          [ $3.to_i, MONTHS[$1], $2.to_i ]
        end
      return nil if month.nil? || !Date.valid_date?(year, month, day)

      Date.new(year, month, day)
    end

    def basic(value)
      squish(value.to_s.unicode_normalize(:nfkc).downcase)
    end

    def squish(text)
      text.strip.gsub(/\s+/, " ")
    end
  end
end
