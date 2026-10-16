require "rails_helper"

# Privacy::Purger (R13): withdrawing consent and deleting an account hard-delete every piece of the
# user's personal data, in the database and in Storage, and leave a pseudonymous audit entry.
# Storage is faked at the HTTP boundary and the Supabase Auth admin API is stubbed.
#
#   Privacy::Purger.new(user_id:, storage: Storage::Client.default).withdraw_consent
#   Privacy::Purger.new(user_id:, storage: Storage::Client.default).delete_account
RSpec.describe "Privacy::Purger" do
  include SchedulingHelpers

  let(:user_id) { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let!(:seeded) { seed_personal_data(user_id, storage: storage) }
  let!(:other_seeded) { seed_personal_data(other_user_id, storage: storage) }

  before { stub_auth_admin }

  def purger(id = user_id)
    Privacy::Purger.new(user_id: id)
  end

  shared_examples "a hard delete of the user's personal data" do |action|
    it "R13: hard-deletes draft and confirmed identity fields, uploads, messages, transcripts and assessments (rows gone, not flagged)" do
      purger.public_send(action)

      expect(remaining_rows(seeded)).to eq(nothing_left)
      expect(Onboarding.where(user_id: user_id)).to be_empty
      expect(Conversation.where(user_id: user_id)).to be_empty
      expect(Assessment.where(user_id: user_id)).to be_empty
    end

    it "R13: deletes the user's document images from Storage with a delete call" do
      purger.public_send(action)

      expect(storage_deletes_for(storage, seeded.image_key)).not_to be_empty
      expect(storage.exists?(seeded.image_key)).to be(false)
      expect(storage.keys.grep(/\A#{user_id}\//)).to be_empty
    end

    it "R13: ends the user's consent, so nothing more is processed for them" do
      purger.public_send(action)

      expect(Consent::Ledger.active?(user_id)).to be(false)
    end

    it "R13: writes one audit entry with only an HMAC actor_ref, the action and a timestamp" do
      expect { purger.public_send(action) }.to change(AuditEvent, :count).by(1)

      event = AuditEvent.last
      expect(AuditEvent.column_names).to contain_exactly("id", "actor_ref", "action", "created_at")
      expect(event.actor_ref).to eq(OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("AUDIT_HMAC_KEY"), user_id))
      expect(event.action).to eq(expected_action)
      expect(event.created_at).to be_within(1.minute).of(Time.current)
      personal = [ user_id, "#{user_id}@example.test", *DocumentHelpers::CLEAN_FIELDS.values, PrivacyHelpers::PERSONAL_MESSAGE ]
      expect(event.attributes.values.map(&:to_s)).to all(satisfy { |value| personal.none? { |p| value.include?(p) } })
    end

    it "R19: touches no other user's data, images, consent or Auth account" do
      purger.public_send(action)

      expect(remaining_rows(other_seeded)).to eq(everything_left(other_seeded))
      expect(storage.exists?(other_seeded.image_key)).to be(true)
      expect(Consent::Ledger.active?(other_user_id)).to be(true)
      expect(auth_admin_delete_for(other_user_id)).not_to have_been_made
    end

    it "R13: can run again for a user with nothing left, without error" do
      purger.public_send(action)

      expect { purger.public_send(action) }.not_to raise_error
      expect(remaining_rows(seeded)).to eq(nothing_left)
    end
  end

  describe "#withdraw_consent" do
    let(:expected_action) { "consent_withdrawn" }

    include_examples "a hard delete of the user's personal data", :withdraw_consent

    it "R13: keeps the Supabase Auth user, so the person can still sign in" do
      purger.withdraw_consent

      expect(any_auth_admin_delete).not_to have_been_made
    end

    it "R13 decision: keeps an active booking (a slot hold isn't personal data under R13)" do
      booking = create_booking(user_id: user_id)

      purger.withdraw_consent

      expect(booking.reload.status).to eq("active")
    end
  end

  describe "#delete_account" do
    let(:expected_action) { "account_deleted" }

    include_examples "a hard delete of the user's personal data", :delete_account

    it "R13: deletes the Supabase Auth user through the admin API with the service role key" do
      purger.delete_account

      expect(auth_admin_delete_for(user_id)).to have_been_made.once
    end

    describe "R13 decision: an active booking on account deletion" do
      it "cancels it and frees the slot for other users" do
        slot = create_slot
        create_booking(user_id: user_id, slot: slot)

        purger.delete_account

        expect(active_bookings_on(slot)).to be_empty
        expect(Slot.open).to include(slot)
        expect(Scheduling::Booker.new(user_id: other_user_id).book(slot_id: slot.id).outcome).to eq(:booked)
      end

      it "leaves no booking rows tied to the deleted user, active or cancelled" do
        create_booking(user_id: user_id)
        create_booking(user_id: user_id, status: "cancelled")

        purger.delete_account

        sql = "SELECT count(*) FROM bookings WHERE user_id = #{ActiveRecord::Base.connection.quote(user_id)}"
        expect(ActiveRecord::Base.connection.select_value(sql).to_i).to eq(0)
      end

      it "R19: leaves another user's booking active" do
        slot = create_slot
        create_booking(user_id: other_user_id, slot: slot)

        purger.delete_account

        expect(active_bookings_on(slot).pluck(:user_id)).to eq([ other_user_id ])
      end
    end
  end
end
