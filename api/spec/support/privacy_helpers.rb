# Helpers for the consent withdrawal and account deletion specs (R13, R19): a user with personal
# data in every place it can live, raw row counts that a soft delete can't fool, and the Supabase
# Auth admin API stubbed at the HTTP boundary.
module PrivacyHelpers
  AUTH_ADMIN_USERS_URL = "#{ENV.fetch("SUPABASE_URL")}/auth/v1/admin/users/".freeze
  SERVICE_ROLE_KEY = ENV.fetch("SUPABASE_SERVICE_ROLE_KEY")
  PERSONAL_MESSAGE = "My name is Jane Q Sample and I live at 123 Fake St".freeze

  # Personal data a user can have, as seeded by seed_personal_data.
  Seeded = Data.define(:onboarding_id, :upload_ids, :pending_upload_id, :image_key, :conversation_id,
                       :message_ids, :assessment_id)

  # Accepts the admin delete for any user and answers like Supabase Auth does.
  def stub_auth_admin(status: 200)
    WebMock.stub_request(:delete, %r{\A#{Regexp.escape(AUTH_ADMIN_USERS_URL)}[^/?]+\z})
      .to_return(status: status, body: "{}", headers: { "Content-Type" => "application/json" })
  end

  def auth_admin_delete_for(user_id)
    a_request(:delete, "#{AUTH_ADMIN_USERS_URL}#{user_id}")
      .with(headers: { "Authorization" => "Bearer #{SERVICE_ROLE_KEY}", "apikey" => SERVICE_ROLE_KEY })
  end

  def any_auth_admin_delete
    a_request(:delete, %r{\A#{Regexp.escape(AUTH_ADMIN_USERS_URL)}})
  end

  # Gives the user consent, a confirmed identity, a confirmed upload (image already gone), a
  # pending upload with an OCR draft and its image in the bucket, a conversation with messages
  # and an assessment draft, and a saved assessment. Written through the models so each spec
  # starts from the same state whichever slice's code is under test.
  def seed_personal_data(user_id, storage:)
    grant_consent(user_id)
    onboarding = Onboarding.for_user(user_id)
    onboarding.confirm_identity!(DocumentHelpers::CLEAN_FIELDS, source: "ocr")

    confirmed = onboarding.document_uploads.create!(storage_key: "#{user_id}/#{SecureRandom.uuid}.jpg",
                                                    status: "confirmed", expires_at: 1.hour.from_now)
    pending = onboarding.document_uploads.create!(
      storage_key: "#{user_id}/#{SecureRandom.uuid}.jpg", status: "pending", expires_at: 1.hour.from_now,
      draft_fields: DocumentHelpers::CLEAN_FIELDS.to_h { |field, value| [ field.to_s, { "value" => value, "confidence" => 93.0, "level" => "high" } ] }
    )
    storage.objects[pending.storage_key] = FakeSupabaseStorage::StoredObject.new(body: "\xFF\xD8\xFFfake".b, content_type: "image/jpeg")

    conversation = Conversation.for_user(user_id)
    conversation.update!(assessment_draft: { "reason" => "Can't sleep since the move" })
    messages = [
      conversation.messages.create!(role: "user", content: PERSONAL_MESSAGE, intent: "provide-details"),
      conversation.messages.create!(role: "assistant", content: "Thanks, Jane. How urgent does this feel?")
    ]
    assessment = Assessment.create!(user_id: user_id, schema_version: "1", data: {
      "reason" => "Can't sleep since the move", "urgency" => "medium", "preferred_window" => "weekday mornings",
      "distress" => false, "notes" => "Lives at 123 Fake St"
    })

    Seeded.new(onboarding_id: onboarding.id, upload_ids: [ confirmed.id, pending.id ], pending_upload_id: pending.id,
               image_key: pending.storage_key, conversation_id: conversation.id, message_ids: messages.map(&:id),
               assessment_id: assessment.id)
  end

  # Rows still in each personal-data table for the seeded user, counted with plain SQL so neither
  # a default scope nor a deleted_at flag can hide a row that is still there.
  def remaining_rows(seeded)
    {
      onboardings: raw_count("onboardings", [ seeded.onboarding_id ]),
      document_uploads: raw_count("document_uploads", seeded.upload_ids),
      conversations: raw_count("conversations", [ seeded.conversation_id ]),
      messages: raw_count("messages", seeded.message_ids),
      assessments: raw_count("assessments", [ seeded.assessment_id ])
    }
  end

  def nothing_left
    { onboardings: 0, document_uploads: 0, conversations: 0, messages: 0, assessments: 0 }
  end

  def everything_left(seeded)
    { onboardings: 1, document_uploads: seeded.upload_ids.size, conversations: 1, messages: seeded.message_ids.size, assessments: 1 }
  end

  def raw_count(table, ids)
    connection = ActiveRecord::Base.connection
    list = ids.map { |id| connection.quote(id) }.join(", ")
    connection.select_value("SELECT count(*) FROM #{connection.quote_table_name(table)} WHERE id IN (#{list})").to_i
  end

  def storage_deletes_for(storage, key)
    storage.requests.select do |request|
      request.method == "DELETE" &&
        (CGI.unescape(request.path) == "/object/#{storage.bucket}/#{key}" ||
          (request.path.match?(%r{\A/object/#{Regexp.escape(storage.bucket)}/?\z}) &&
            JSON.parse(request.body.to_s).fetch("prefixes", []).include?(key)))
    end
  end

  # Follows a signed URL the way a browser would: no service key, just the token in the URL.
  def fetch_signed_url(url)
    Net::HTTP.get_response(URI(url))
  end
end

RSpec.configure do |config|
  config.include PrivacyHelpers
end
