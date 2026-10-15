# Consent, the onboarding record and document uploads (R5, R12, R17). Identity values and the OCR
# draft are encrypted with Active Record encryption, so those columns are text. RLS is enabled on
# every table after migrating (lib/boot/row_level_security.rb).
class CreateConsentsOnboardingsAndDocumentUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :consents, id: :uuid do |t|
      t.uuid :user_id, null: false, index: true
      t.string :text_version, null: false
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    create_table :onboardings, id: :uuid do |t|
      t.uuid :user_id, null: false, index: { unique: true }
      t.string :step
      t.text :full_name
      t.text :date_of_birth
      t.text :address
      t.string :identity_source
      t.datetime :confirmed_at
      t.timestamps
      t.check_constraint "identity_source IN ('ocr', 'manual')", name: "onboardings_identity_source_check"
    end

    create_table :document_uploads, id: :uuid do |t|
      t.references :onboarding, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :storage_key, null: false, index: { unique: true }
      t.string :status, null: false, default: "pending"
      t.text :draft_fields
      t.string :ocr_reason
      t.datetime :expires_at, null: false, index: true
      t.timestamps
      t.check_constraint "status IN ('pending', 'confirmed')", name: "document_uploads_status_check"
    end
  end
end
