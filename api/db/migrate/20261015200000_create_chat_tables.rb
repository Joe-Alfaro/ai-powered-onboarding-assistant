# Chat state (R1, R2). Message text, the assessment draft and the saved assessment are encrypted
# with Active Record encryption, so the columns are text. The draft lives on the conversation
# because every assessments row must validate against app/schemas/assessment.json.
class CreateChatTables < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations, id: :uuid do |t|
      t.uuid :user_id, null: false, index: { unique: true }
      t.text :assessment_draft
      t.timestamps
    end

    create_table :messages, id: :uuid do |t|
      t.references :conversation, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false
      t.text :content, null: false
      t.string :intent
      t.datetime :created_at, null: false
      t.check_constraint "role IN ('user', 'assistant')", name: "messages_role_check"
    end

    create_table :assessments, id: :uuid do |t|
      t.uuid :user_id, null: false, index: { unique: true }
      t.text :data, null: false
      t.string :schema_version, null: false
      t.timestamps
    end
  end
end
