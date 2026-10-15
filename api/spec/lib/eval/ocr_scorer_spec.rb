require "rails_helper"
require "rake"

RSpec.describe "Eval::OcrScorer" do
  let(:fields) { %i[full_name date_of_birth address] }

  # Writes a golden directory with placeholder images; the fake reader never opens them.
  def golden_dir_with(labels)
    dir = Pathname(Dir.mktmpdir)
    labels.each { |label| dir.join(label[:image]).write("placeholder") }
    dir.join("labels.json").write(JSON.generate(labels))
    dir
  end

  def label(id, hard: false)
    {
      id: id, image: "#{id}.png", category: "clean", hard: hard, hard_reason: (hard ? "near miss" : nil),
      expected: { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" }
    }
  end

  let(:correct) { { full_name: "JANE Q SAMPLE", date_of_birth: "03/14/1985", address: "123 FAKE STREET SPRINGFIELD ZZ 00000" } }

  let(:golden_dir) { golden_dir_with([ label("001"), label("002"), label("003", hard: true), label("004", hard: true) ]) }

  after { FileUtils.rm_rf(golden_dir) }

  def score(reads)
    reader = ->(path) { reads.fetch(File.basename(path, ".png")) }
    Eval::OcrScorer.new(golden_dir: golden_dir, reader: reader).call
  end

  it "reports per-field accuracy over all documents using the documented field match" do
    report = score(
      "001" => correct,
      "002" => correct.merge(address: nil),
      "003" => correct.merge(date_of_birth: "03/15/1985"),
      "004" => correct.merge(full_name: "Sample, Jane Q")
    )

    expect(report[:all]).to eq(full_name: 0.75, date_of_birth: 0.75, address: 0.75)
    expect(report[:counts]).to eq(all: 4, hard: 2)
  end

  it "reports the hard cases separately" do
    report = score(
      "001" => correct,
      "002" => correct,
      "003" => correct.merge(address: "128 Fake St, Springfield, ZZ 00000"),
      "004" => correct.merge(address: nil)
    )

    expect(report[:hard]).to eq(full_name: 1.0, date_of_birth: 1.0, address: 0.0)
    expect(report[:all][:address]).to eq(0.5)
  end

  it "counts every field of a document as a miss when reading it raises, and keeps scoring" do
    reads = { "001" => correct, "002" => correct, "003" => correct }
    reader = lambda do |path|
      id = File.basename(path, ".png")
      raise "boom" if id == "004"

      reads.fetch(id)
    end

    report = Eval::OcrScorer.new(golden_dir: golden_dir, reader: reader).call

    expect(report[:all]).to eq(full_name: 0.75, date_of_birth: 0.75, address: 0.75)
  end

  it "passes each image's full path to the reader" do
    seen = []
    reader = ->(path) { seen << path.to_s; correct }

    Eval::OcrScorer.new(golden_dir: golden_dir, reader: reader).call

    expect(seen).to match_array(%w[001 002 003 004].map { |id| golden_dir.join("#{id}.png").to_s })
  end

  describe "with the default reader (real Tesseract)" do
    it "reads images through Ocr::Extractor and Ocr::FieldMapper" do
      dir = Pathname(Dir.mktmpdir)
      FileUtils.cp(ocr_fixture("clean_id.png"), dir.join("001.png"))
      dir.join("labels.json").write(JSON.generate([ label("001") ]))

      report = Eval::OcrScorer.new(golden_dir: dir).call

      expect(report[:all]).to eq(full_name: 1.0, date_of_birth: 1.0, address: 1.0)
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  # R4: field-level accuracy on the committed golden set is at least 90% for each field.
  it "scores at least 90% on every field of the committed golden set" do
    report = Eval::OcrScorer.new(golden_dir: Rails.root.join("eval/golden")).call

    fields.each { |field| expect(report[:all][field]).to be >= 0.9, "#{field} accuracy was #{report[:all][field]}" }
  end
end

RSpec.describe "rake ai:eval:ocr" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("ai:eval:ocr") }

  around do |example|
    original = ENV.fetch("GOLDEN_DIR", nil)
    example.run
  ensure
    ENV["GOLDEN_DIR"] = original
  end

  it "prints per-field OCR accuracy, with hard cases reported separately" do
    dir = Pathname(Dir.mktmpdir)
    FileUtils.cp(ocr_fixture("clean_id.png"), dir.join("001.png"))
    FileUtils.cp(ocr_fixture("partial_id.png"), dir.join("002.png"))
    expected = { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" }
    dir.join("labels.json").write(JSON.generate([
      { id: "001", image: "001.png", category: "clean", hard: false, hard_reason: nil, expected: expected },
      { id: "002", image: "002.png", category: "clean", hard: true, hard_reason: "address missing", expected: expected }
    ]))
    ENV["GOLDEN_DIR"] = dir.to_s

    task = Rake::Task["ai:eval:ocr"]
    task.reenable
    output = capture_stdout { task.invoke }

    all_section, hard_section = output.split(/hard cases/i, 2)
    expect(hard_section).not_to be_nil
    expect(all_section).to match(/full_name\D+100(\.0)?%/).and match(/address\D+50(\.0)?%/)
    expect(hard_section).to match(/full_name\D+100(\.0)?%/).and match(/address\D+0(\.0)?%/)
    expect(hard_section).to match(/date_of_birth\D+\d+(\.\d)?%/)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
