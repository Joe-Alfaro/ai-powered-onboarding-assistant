require "rails_helper"
require "open3"

# R26: the synthetic OCR golden set.
RSpec.describe "OCR golden set" do
  let(:golden_dir) { Rails.root.join("eval/golden") }
  let(:labels) { JSON.parse(golden_dir.join("labels.json").read) }
  let(:categories) { %w[clean phone_photo skew glare] }

  describe "labels.json" do
    it "has 30 labeled documents" do
      expect(labels.size).to eq(30)
    end

    it "gives every document the documented keys" do
      labels.each do |label|
        expect(label.keys).to contain_exactly("id", "image", "category", "hard", "hard_reason", "expected")
        expect(label["expected"].keys).to contain_exactly("full_name", "date_of_birth", "address")
      end
    end

    it "uses unique ids and images" do
      expect(labels.map { |label| label["id"] }.uniq.size).to eq(30)
      expect(labels.map { |label| label["image"] }.uniq.size).to eq(30)
    end

    it "gives each document an expected name, date of birth and address" do
      labels.each do |label|
        expected = label["expected"]

        expect(expected["full_name"]).to be_a(String).and(match(/\S/))
        expect(expected["address"]).to be_a(String).and(match(/\S/))
        expect(expected["date_of_birth"]).to match(/\A\d{4}-\d{2}-\d{2}\z/)
        expect(Date.iso8601(expected["date_of_birth"])).to be < Date.current
      end
    end
  end

  describe "images" do
    it "commits one readable PNG or JPEG for every label" do
      labels.each do |label|
        path = golden_dir.join(label["image"])
        expect(path).to exist

        magic = path.binread(4).bytes
        expect(magic).to eq([ 0x89, 0x50, 0x4E, 0x47 ]).or(start_with(0xFF, 0xD8, 0xFF))
      end
    end
  end

  describe "coverage of conditions" do
    it "includes clean scans, phone photos, mild skew and glare" do
      expect(labels.map { |label| label["category"] }.uniq).to contain_exactly(*categories)
    end

    it "includes at least 3 hard near-miss cases, each labeled with a reason" do
      hard = labels.select { |label| label["hard"] == true }

      expect(hard.size).to be >= 3
      hard.each { |label| expect(label["hard_reason"]).to be_a(String).and(match(/\S/)) }
    end

    it "marks every other document as not hard, with no reason" do
      labels.reject { |label| label["hard"] }.each do |label|
        expect(label["hard"]).to be(false)
        expect(label["hard_reason"]).to be_nil
      end
    end
  end

  describe "obviously fake data" do
    it "uses the fictional state ZZ and an unassigned ZIP starting with 000 in every address" do
      labels.each do |label|
        expect(label["expected"]["address"]).to match(/\bZZ,? 000\d{2}\z/)
      end
    end
  end

  describe "the generator script" do
    it "regenerates 30 images and the same labels.json" do
      Dir.mktmpdir do |out|
        _output, status = Open3.capture2e(
          Rails.root.join("eval/generate_golden_set").to_s, "--out", out, chdir: Rails.root.to_s
        )

        expect(status).to be_success
        expect(JSON.parse(File.read(File.join(out, "labels.json")))).to eq(labels)
        labels.each { |label| expect(File).to exist(File.join(out, label["image"])) }
      end
    end
  end
end
