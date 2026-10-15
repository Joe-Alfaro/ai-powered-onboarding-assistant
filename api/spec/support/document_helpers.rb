# Helpers for the document upload specs: fixture files, consent, a stubbed OCR engine and the
# fake Storage bucket.
module DocumentHelpers
  CONSENT_TEXT_VERSION = "2026-10-15".freeze
  CLEAN_FIELDS = { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" }.freeze

  # Stands in for Ocr::Extractor. It records each image it was handed (path and first bytes, read
  # while the file still exists) and returns a scripted Ocr::Extraction, or runs a block instead.
  class FakeExtractor
    Call = Data.define(:path, :head)

    attr_reader :calls

    def initialize(extraction = nil, &block)
      @extraction = extraction
      @block = block
      @calls = []
    end

    def call(path)
      @calls << Call.new(path: path, head: File.file?(path) ? File.binread(path, 16) : nil)
      @block ? @block.call(path) : @extraction
    end

    def called?
      @calls.any?
    end
  end

  def document_fixture(name)
    Rails.root.join("spec/fixtures/files/documents", name).to_s
  end

  def upload_file(path, content_type: "image/jpeg", filename: File.basename(path))
    Rack::Test::UploadedFile.new(path, content_type, true, original_filename: filename)
  end

  def upload_bytes(bytes, content_type: "image/jpeg", filename: "photo.jpg")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, true, original_filename: filename)
  end

  def grant_consent(user_id, text_version: CONSENT_TEXT_VERSION)
    Consent::Ledger.grant!(user_id: user_id, text_version: text_version)
  end

  # What Tesseract reads from a clean card, all well above the threshold.
  def clean_extraction
    build_extraction(
      [ [ "NAME", 95 ], [ "Jane", 94 ], [ "Q", 92 ], [ "Sample", 93 ] ],
      [ [ "DOB", 95 ], [ "03/14/1985", 91 ] ],
      [ [ "ADDRESS", 95 ], [ "123", 92 ], [ "Fake", 93 ], [ "St,", 90 ], [ "Springfield,", 91 ], [ "ZZ", 90 ], [ "00000", 92 ] ],
      [ [ "ID", 95 ], [ "NO", 95 ], [ "D1234567", 94 ] ]
    )
  end

  # Replaces the OCR engine for the example. Pass an extraction to return, or a block to run.
  def stub_extractor(extraction = clean_extraction, &block)
    fake = FakeExtractor.new(extraction, &block)
    allow(Ocr::Extractor).to receive(:new).and_return(fake)
    fake
  end

  def stub_storage
    FakeSupabaseStorage.new.install
  end

  def post_document(user_id, file)
    post "/documents", params: { file: file }, headers: auth_headers(user_id)
  end

  def document_body
    response.parsed_body.fetch("document")
  end

  def error_body
    response.parsed_body.fetch("error")
  end

  # Every identity value on the user's onboarding record, empty if there is no record.
  def identity_values(user_id)
    onboarding = Onboarding.find_by(user_id: user_id)
    return {} if onboarding.nil?

    { full_name: onboarding.full_name, date_of_birth: onboarding.date_of_birth, address: onboarding.address }.compact
  end
end

RSpec.configure do |config|
  config.include DocumentHelpers
end
