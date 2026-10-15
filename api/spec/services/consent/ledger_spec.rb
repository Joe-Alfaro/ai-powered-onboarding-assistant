require "rails_helper"

RSpec.describe "Consent::Ledger" do
  let(:user_id) { SecureRandom.uuid }

  describe "R12: each consent is stored with the user, a timestamp and the consent text version" do
    it "grant! records the user, the time it was granted and the text version" do
      freeze_time do
        Consent::Ledger.grant!(user_id: user_id, text_version: "2026-10-15")

        consent = Consent.find_by!(user_id: user_id)
        expect(consent.text_version).to eq("2026-10-15")
        expect(consent.granted_at).to eq(Time.current)
        expect(consent.revoked_at).to be_nil
      end
    end

    it "refuses a grant with no text version" do
      expect { Consent::Ledger.grant!(user_id: user_id, text_version: "") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Consent.where(user_id: user_id)).to be_empty
    end
  end

  describe "active?" do
    it "is false for a user who never consented" do
      expect(Consent::Ledger.active?(user_id)).to be(false)
    end

    it "is true after a grant" do
      Consent::Ledger.grant!(user_id: user_id, text_version: "2026-10-15")

      expect(Consent::Ledger.active?(user_id)).to be(true)
    end

    it "is per user: another user's consent doesn't count" do
      Consent::Ledger.grant!(user_id: SecureRandom.uuid, text_version: "2026-10-15")

      expect(Consent::Ledger.active?(user_id)).to be(false)
    end
  end

  describe "revoke!" do
    it "ends the active consent and records when" do
      Consent::Ledger.grant!(user_id: user_id, text_version: "2026-10-15")

      freeze_time do
        Consent::Ledger.revoke!(user_id: user_id)

        expect(Consent::Ledger.active?(user_id)).to be(false)
        expect(Consent.find_by!(user_id: user_id).revoked_at).to eq(Time.current)
      end
    end

    it "does nothing harmful for a user with no consent" do
      expect { Consent::Ledger.revoke!(user_id: user_id) }.not_to raise_error
      expect(Consent::Ledger.active?(user_id)).to be(false)
    end

    it "lets the user consent again later, as a new record with its own version" do
      Consent::Ledger.grant!(user_id: user_id, text_version: "2026-10-15")
      Consent::Ledger.revoke!(user_id: user_id)
      Consent::Ledger.grant!(user_id: user_id, text_version: "2026-11-01")

      expect(Consent::Ledger.active?(user_id)).to be(true)
      expect(Consent.where(user_id: user_id).order(:granted_at).pluck(:text_version)).to eq(%w[2026-10-15 2026-11-01])
    end
  end
end
