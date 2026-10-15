require "rails_helper"

# The upload flow with the real OCR engine (Tesseract and libvips), on the made-up sample card.
# Most document specs stub Ocr::Extractor; these two prove the real pieces fit together.
RSpec.describe "POST /documents with real OCR", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }

  before { grant_consent(user_id) }

  def expect_sample_card_read
    expect(response).to have_http_status(:ok)
    expect(document_body["manual_entry"]).to be(false)
    DocumentHelpers::CLEAN_FIELDS.each do |field, expected|
      value = document_body.dig("fields", field.to_s, "value")
      expect(Eval::FieldMatch.match?(field, expected, value)).to be(true), "#{field}: read #{value.inspect}"
    end
    expect(identity_values(user_id)).to be_empty
  end

  it "reads name, date of birth and address from a JPEG into the draft" do
    post_document(user_id, upload_file(document_fixture("id.jpg")))

    expect_sample_card_read
  end

  it "R14: converts a HEIC photo and reads it" do
    post_document(user_id, upload_file(document_fixture("id.heic"), content_type: "image/heic"))

    expect_sample_card_read
  end
end
