require "rails_helper"

# R4: the scorer's field-level match is exactly the normalization documented in eval/README.md.
RSpec.describe "Eval::FieldMatch" do
  def match?(field, expected, read)
    Eval::FieldMatch.match?(field, expected, read)
  end

  describe "the examples table in eval/README.md" do
    readme = Rails.root.join("eval/README.md").read
    table = readme.split("### Match examples", 2).last.to_s
    rows = table.lines.grep(/\A\|/).drop(2).map do |line|
      line.strip.delete_prefix("|").delete_suffix("|").split("|").map do |cell|
        cell = cell.strip
        cell.start_with?("`") && cell.end_with?("`") ? cell[1..-2] : cell
      end
    end

    it "documents match examples for every field" do
      expect(rows.map(&:first).uniq).to contain_exactly("full_name", "date_of_birth", "address")
      expect(rows.map(&:last).uniq).to contain_exactly("yes", "no")
    end

    rows.each do |field, expected, read, outcome|
      it "#{field}: #{expected.inspect} vs #{read.inspect} is #{outcome == 'yes' ? 'a match' : 'not a match'}" do
        expect(match?(field.to_sym, expected, read)).to be(outcome == "yes")
      end
    end
  end

  describe "rules for every field" do
    it "never matches a field the OCR didn't read" do
      expect(match?(:full_name, "Jane Sample", nil)).to be(false)
      expect(match?(:date_of_birth, "1985-03-14", nil)).to be(false)
      expect(match?(:address, "123 Fake St", nil)).to be(false)
    end

    it "ignores case" do
      expect(match?(:full_name, "jane sample", "JANE SAMPLE")).to be(true)
      expect(match?(:address, "123 fake st", "123 FAKE ST")).to be(true)
    end

    it "applies Unicode NFKC normalization" do
      expect(match?(:full_name, "Jane Sample", "Ｊａｎｅ Ｓａｍｐｌｅ")).to be(true)
    end

    it "trims and collapses whitespace, including tabs and newlines" do
      expect(match?(:full_name, "Jane Q Sample", " Jane\tQ \n Sample ")).to be(true)
      expect(match?(:address, "123 Fake St, Springfield", "123  Fake\nSt,   Springfield")).to be(true)
    end

    it "accepts string or symbol field names" do
      expect(match?("full_name", "Jane", "JANE")).to be(true)
    end
  end

  describe "full_name" do
    it "drops periods and commas but keeps word order" do
      expect(match?(:full_name, "Jane Q. Sample", "Jane Q Sample")).to be(true)
      expect(match?(:full_name, "Jane Sample", "Sample, Jane")).to be(false)
    end

    it "keeps hyphens and apostrophes significant" do
      expect(match?(:full_name, "Mary-Ann O'Testcase", "mary-ann o'testcase")).to be(true)
      expect(match?(:full_name, "Mary-Ann O'Testcase", "Mary Ann O'Testcase")).to be(false)
      expect(match?(:full_name, "Mary-Ann O'Testcase", "Mary-Ann OTestcase")).to be(false)
    end
  end

  describe "date_of_birth" do
    it "accepts ISO dates" do
      expect(match?(:date_of_birth, "1985-03-14", "1985-03-14")).to be(true)
    end

    it "reads numeric dates month first, with slashes or hyphens and optional leading zeros" do
      expect(match?(:date_of_birth, "1985-03-04", "03/04/1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-04", "3/4/1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-04", "03-04-1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-04", "04/03/1985")).to be(false)
    end

    it "accepts day-month-year and month-day-year with full or abbreviated month names in any case" do
      expect(match?(:date_of_birth, "1985-03-14", "14 MAR 1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-14", "14 march 1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-14", "Mar 14 1985")).to be(true)
      expect(match?(:date_of_birth, "1985-03-14", "March 14, 1985")).to be(true)
    end

    it "never matches two-digit years" do
      expect(match?(:date_of_birth, "1985-03-14", "03/14/85")).to be(false)
    end

    it "never matches impossible or unparseable dates" do
      expect(match?(:date_of_birth, "1985-02-28", "02/30/1985")).to be(false)
      expect(match?(:date_of_birth, "1985-03-14", "O3/14/1985")).to be(false)
      expect(match?(:date_of_birth, "1985-03-14", "sometime in 1985")).to be(false)
    end

    it "doesn't match two equal strings that aren't valid dates" do
      expect(match?(:date_of_birth, "99/99/9999", "99/99/9999")).to be(false)
    end

    it "compares the dates, not the strings" do
      expect(match?(:date_of_birth, "1985-03-14", "1985-03-15")).to be(false)
    end
  end

  describe "address" do
    it "drops periods and treats commas as spaces" do
      expect(match?(:address, "45 N Example Ave, Testville", "45 N. Example Ave. Testville")).to be(true)
      expect(match?(:address, "123 Fake St,Springfield", "123 Fake St Springfield")).to be(true)
    end

    {
      "street" => "st", "avenue" => "ave", "road" => "rd", "boulevard" => "blvd",
      "drive" => "dr", "lane" => "ln", "court" => "ct", "place" => "pl",
      "apartment" => "apt", "suite" => "ste", "north" => "n", "south" => "s",
      "east" => "e", "west" => "w"
    }.each do |word, abbreviation|
      it "treats #{word.inspect} and #{abbreviation.inspect} as the same word" do
        expect(match?(:address, "1 Mock #{abbreviation}", "1 MOCK #{word.upcase}")).to be(true)
        expect(match?(:address, "1 Mock #{word}", "1 Mock #{abbreviation}")).to be(true)
      end
    end

    it "abbreviates whole words only" do
      expect(match?(:address, "1 Eastview Rd", "1 Eview Rd")).to be(false)
      expect(match?(:address, "1 Streeter Rd", "1 Ster Rd")).to be(false)
    end

    it "requires digits to match exactly" do
      expect(match?(:address, "123 Fake St", "128 Fake St")).to be(false)
      expect(match?(:address, "1 Fake St, ZZ 00000", "1 Fake St, ZZ OOOOO")).to be(false)
    end

    it "doesn't match a partial address" do
      expect(match?(:address, "123 Fake St, Springfield, ZZ 00000", "123 Fake St")).to be(false)
    end
  end

  it "rejects an unknown field" do
    expect { match?(:favorite_color, "blue", "blue") }.to raise_error(ArgumentError)
  end
end
