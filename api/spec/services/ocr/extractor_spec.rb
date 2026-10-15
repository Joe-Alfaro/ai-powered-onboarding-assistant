require "rails_helper"

# Runs real Tesseract on the fixture images in spec/fixtures/files/ocr (regenerate them with make_fixtures there).
RSpec.describe "Ocr::Extractor" do
  subject(:extractor) { Ocr::Extractor.new }

  let(:mapper) { Ocr::FieldMapper.new(threshold: 60) }
  let(:expected) do
    { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" }
  end

  def read_fields(name)
    mapper.call(extractor.call(ocr_fixture(name)))
  end

  def expect_fields_to_match(result, *fields)
    fields.each do |field|
      reading = result.fields[field]
      expect(reading).not_to be_nil, "#{field} wasn't read"
      expect(Eval::FieldMatch.match?(field, expected[field], reading.value)).to be(true),
        "#{field}: expected #{expected[field].inspect}, read #{reading.value.inspect}"
    end
  end

  describe "a clean scan" do
    it "returns the text as lines of words, each with a confidence from 0 to 100" do
      extraction = extractor.call(ocr_fixture("clean_id.png"))

      expect(extraction.failed?).to be(false)
      expect(extraction.empty?).to be(false)
      expect(extraction.text).to match(/SAMPLE/i)
      words = extraction.lines.flatten
      expect(words).not_to be_empty
      words.each { |word| expect(word.confidence).to be_between(0, 100) }
      expect(extraction.confidence).to be >= 60
    end

    it "R4: yields name, date of birth and address through the field mapper" do
      result = read_fields("clean_id.png")

      expect(result.manual_entry?).to be(false)
      expect_fields_to_match(result, :full_name, :date_of_birth, :address)
    end
  end

  describe "a phone photo with mild skew, blur and noise" do
    it "R4: still yields name, date of birth and address after preprocessing" do
      result = read_fields("photo_skewed_id.jpg")

      expect(result.manual_entry?).to be(false)
      expect_fields_to_match(result, :full_name, :date_of_birth, :address)
    end
  end

  describe "a card with no address" do
    it "R11: returns the name and date of birth with confidences and leaves the address nil" do
      result = read_fields("partial_id.png")

      expect(result.manual_entry?).to be(false)
      expect_fields_to_match(result, :full_name, :date_of_birth)
      expect(result.fields[:full_name].confidence).to be_between(0, 100)
      expect(result.fields[:address]).to be_nil
    end
  end

  describe "R10: failures give a manual-entry result and never raise" do
    it "returns an empty extraction for a blank image" do
      extraction = extractor.call(ocr_fixture("blank.png"))

      expect(extraction.empty?).to be(true)
      expect(mapper.call(extraction)).to have_attributes(manual_entry?: true, reason: :no_text)
    end

    it "returns a failed extraction for a corrupt image" do
      extraction = nil
      expect { extraction = extractor.call(ocr_fixture("corrupt.png")) }.not_to raise_error

      expect(extraction.failed?).to be(true)
      expect(extraction.error).to be_present
      expect(mapper.call(extraction)).to have_attributes(manual_entry?: true, reason: :ocr_error)
    end

    it "returns a failed extraction for a missing file" do
      extraction = nil
      expect { extraction = extractor.call(ocr_fixture("does_not_exist.png")) }.not_to raise_error

      expect(extraction.failed?).to be(true)
      expect(mapper.call(extraction)).to have_attributes(manual_entry?: true, reason: :ocr_error)
    end

    it "returns a failed extraction when the Tesseract binary can't be run" do
      original_path = ENV.fetch("PATH")
      extraction = nil

      begin
        ENV["PATH"] = Dir.mktmpdir
        expect { extraction = extractor.call(ocr_fixture("clean_id.png")) }.not_to raise_error
      ensure
        ENV["PATH"] = original_path
      end

      expect(extraction.failed?).to be(true)
      expect(mapper.call(extraction)).to have_attributes(manual_entry?: true, reason: :ocr_error)
    end
  end
end
