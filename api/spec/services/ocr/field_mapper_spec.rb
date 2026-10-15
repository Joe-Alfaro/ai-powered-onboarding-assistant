require "rails_helper"
require "net/http"

RSpec.describe "Ocr::FieldMapper" do
  subject(:mapper) { Ocr::FieldMapper.new(threshold: 60) }

  let(:fields) { %i[full_name date_of_birth address] }

  def full_card(confidence = 95)
    lines_at(
      confidence,
      "SAMPLE IDENTIFICATION CARD",
      "NAME JANE Q SAMPLE",
      "DOB 03/14/1985",
      "ADDRESS 123 FAKE ST",
      "SPRINGFIELD, ZZ 00000",
      "ISS 01/02/2020",
      "EXP 01/02/2030"
    )
  end

  describe "R4: maps OCR text to name, date of birth and address" do
    it "returns all three fields from a clean read" do
      result = mapper.call(build_extraction(*full_card))

      expect(result.manual_entry?).to be(false)
      expect(result.fields.keys).to contain_exactly(*fields)
      expect(result.fields[:full_name].value).to match(/\Ajane q sample\z/i)
      expect(result.fields[:date_of_birth].value).to eq("1985-03-14")
      expect(result.fields[:address].value).to match(/\A123 fake st,? springfield,? zz 00000\z/i)
    end

    it "accepts the DATE OF BIRTH and ADDR label variants and named-month dates" do
      result = mapper.call(build_extraction(*lines_at(
        95, "NAME JANE Q SAMPLE", "DATE OF BIRTH 14 MAR 1985", "ADDR 123 FAKE ST", "SPRINGFIELD, ZZ 00000"
      )))

      expect(result.fields[:date_of_birth].value).to eq("1985-03-14")
      expect(result.fields[:address].value).to match(/\A123 fake st,? springfield,? zz 00000\z/i)
    end

    it "takes the date of birth, not the issue or expiry date, when the card has several dates" do
      result = mapper.call(build_extraction(*lines_at(
        95, "ISS 01/02/2020", "EXP 01/02/2030", "NAME JANE Q SAMPLE", "DOB 03/14/1985", "ADDRESS 123 FAKE ST"
      )))

      expect(result.fields[:date_of_birth].value).to eq("1985-03-14")
    end

    it "stops the address at the next label" do
      result = mapper.call(build_extraction(*full_card))

      expect(result.fields[:address].value).not_to match(/ISS|EXP|2020|2030/i)
    end

    it "makes no network calls (no LLM in the OCR path)" do
      expect(Net::HTTP).not_to receive(:start)
      expect(Net::HTTP).not_to receive(:new)

      mapper.call(build_extraction(*full_card))
    end
  end

  describe "R11: partial extraction without fabrication" do
    it "returns the fields it read with a confidence and leaves the unread fields nil" do
      result = mapper.call(build_extraction(*lines_at(95, "SAMPLE IDENTIFICATION CARD", "NAME JANE Q SAMPLE")))

      expect(result.manual_entry?).to be(false)
      expect(result.fields[:full_name]).to have_attributes(value: match(/\Ajane q sample\z/i), confidence: be_between(0, 100))
      expect(result.fields[:date_of_birth]).to be_nil
      expect(result.fields[:address]).to be_nil
    end

    it "always returns all three keys, even when a field is missing" do
      result = mapper.call(build_extraction(*lines_at(95, "NAME JANE Q SAMPLE")))

      expect(result.fields.keys).to contain_exactly(*fields)
    end

    it "never fills the date of birth from an issue or expiry date" do
      result = mapper.call(build_extraction(*lines_at(95, "NAME JANE Q SAMPLE", "ISS 01/02/2020", "EXP 01/02/2030")))

      expect(result.fields[:date_of_birth]).to be_nil
    end

    it "returns nil for a date of birth that isn't a real date, rather than guessing a correction" do
      result = mapper.call(build_extraction(*lines_at(95, "NAME JANE Q SAMPLE", "DOB 02/30/1985")))

      expect(result.fields[:date_of_birth]).to be_nil
    end

    it "returns nil for a date of birth in the future" do
      result = mapper.call(build_extraction(*lines_at(95, "NAME JANE Q SAMPLE", "DOB 03/14/#{Date.current.year + 1}")))

      expect(result.fields[:date_of_birth]).to be_nil
    end

    it "returns nil for a label with no value after it" do
      result = mapper.call(build_extraction(*lines_at(95, "NAME JANE Q SAMPLE", "DOB", "ADDRESS")))

      expect(result.fields[:date_of_birth]).to be_nil
      expect(result.fields[:address]).to be_nil
    end

    it "doesn't take the card title or another label's value as the name" do
      result = mapper.call(build_extraction(*lines_at(95, "SAMPLE IDENTIFICATION CARD", "DOB 03/14/1985")))

      expect(result.fields[:full_name]).to be_nil
      expect(result.fields[:date_of_birth].value).to eq("1985-03-14")
    end

    it "marks fields read with low confidence differently from high-confidence fields" do
      extraction = build_extraction(
        *lines_at(95, "NAME JANE Q SAMPLE", "DOB 03/14/1985"),
        [ [ "ADDRESS", 95 ], [ "123", 40 ], [ "FAKE", 40 ], [ "ST", 40 ] ]
      )

      result = mapper.call(extraction)

      expect(result.manual_entry?).to be(false)
      expect(result.fields[:full_name].level).to eq(:high)
      expect(result.fields[:date_of_birth].level).to eq(:high)
      expect(result.fields[:address].level).to eq(:low)
      expect(result.fields[:address].confidence).to be < result.fields[:full_name].confidence
    end

    it "keeps a low-confidence value as read, without altering it" do
      extraction = build_extraction(
        *lines_at(95, "NAME JANE Q SAMPLE", "DOB 03/14/1985"),
        [ [ "ADDRESS", 95 ], [ "123", 40 ], [ "FAKE", 40 ], [ "ST", 40 ] ]
      )

      expect(mapper.call(extraction).fields[:address].value).to match(/\A123 fake st\z/i)
    end

    it "treats a field whose confidence equals the threshold as high confidence" do
      result = mapper.call(build_extraction(*lines_at(60, "NAME JANE Q SAMPLE")))

      expect(result.manual_entry?).to be(false)
      expect(result.fields[:full_name].level).to eq(:high)
    end
  end

  describe "R10: OCR failure signals manual entry and never raises" do
    def expect_manual_entry(result, reason)
      expect(result.manual_entry?).to be(true)
      expect(result.reason).to eq(reason)
      expect(result.fields).to eq(full_name: nil, date_of_birth: nil, address: nil)
    end

    it "signals manual entry when OCR returned no text" do
      expect_manual_entry(mapper.call(build_extraction), :no_text)
    end

    it "signals manual entry when OCR returned only whitespace" do
      expect_manual_entry(mapper.call(build_extraction([ [ " ", 90 ] ], [ [ "", 90 ] ])), :no_text)
    end

    it "signals manual entry when the overall confidence is below the threshold, even if labels parse" do
      expect_manual_entry(mapper.call(build_extraction(*full_card(30))), :low_confidence)
    end

    it "signals manual entry when OCR threw" do
      expect_manual_entry(mapper.call(build_extraction(error: "tesseract exited with status 1")), :ocr_error)
    end

    it "signals manual entry when the text has no recognizable field" do
      expect_manual_entry(
        mapper.call(build_extraction(*lines_at(95, "THE QUICK BROWN FOX", "JUMPS OVER THE LAZY DOG"))),
        :no_fields
      )
    end

    it "doesn't raise on garbage text" do
      garbage = build_extraction(*lines_at(95, "NAME", "DOB DOB DOB 00/00/0000", "ADDRESS , , ,", "~~~ |||| ###"))

      expect { mapper.call(garbage) }.not_to raise_error
    end

    it "doesn't signal manual entry for a confident read" do
      result = mapper.call(build_extraction(*full_card))

      expect(result.manual_entry?).to be(false)
      expect(result.reason).to be_nil
    end

    describe "the threshold" do
      around do |example|
        original = ENV.fetch("OCR_CONFIDENCE_THRESHOLD", nil)
        example.run
      ensure
        ENV["OCR_CONFIDENCE_THRESHOLD"] = original
      end

      it "comes from OCR_CONFIDENCE_THRESHOLD by default" do
        ENV["OCR_CONFIDENCE_THRESHOLD"] = "80"

        expect(Ocr::FieldMapper.new.call(build_extraction(*full_card(70))).manual_entry?).to be(true)
        expect(Ocr::FieldMapper.new.call(build_extraction(*full_card(85))).manual_entry?).to be(false)
      end

      it "has a default when OCR_CONFIDENCE_THRESHOLD isn't set" do
        ENV.delete("OCR_CONFIDENCE_THRESHOLD")

        expect(Ocr::FieldMapper.new.call(build_extraction(*full_card(5))).manual_entry?).to be(true)
        expect(Ocr::FieldMapper.new.call(build_extraction(*full_card(95))).manual_entry?).to be(false)
      end
    end
  end
end
