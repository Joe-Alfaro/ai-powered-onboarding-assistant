# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_15_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "assessments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.text "data", null: false
    t.string "schema_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_assessments_on_user_id", unique: true
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "actor_ref", null: false
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.index ["actor_ref"], name: "index_audit_events_on_actor_ref"
  end

  create_table "bookings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "slot_id", null: false
    t.uuid "user_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slot_id"], name: "index_bookings_on_slot_id_active", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["user_id"], name: "index_bookings_on_user_id_active", unique: true, where: "((status)::text = 'active'::text)"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'cancelled'::character varying]::text[])", name: "bookings_status_check"
  end

  create_table "conversations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.text "assessment_draft"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_conversations_on_user_id", unique: true
  end

  create_table "messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "conversation_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "intent"
    t.datetime "created_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.check_constraint "role::text = ANY (ARRAY['user'::character varying, 'assistant'::character varying]::text[])", name: "messages_role_check"
  end

  create_table "slots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.timestamptz "starts_at", null: false
    t.timestamptz "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["starts_at"], name: "index_slots_on_starts_at"
  end

  add_foreign_key "bookings", "slots"
  add_foreign_key "messages", "conversations", on_delete: :cascade
end
