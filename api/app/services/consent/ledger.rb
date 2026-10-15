module Consent
  # The seam chat uses to stop LLM calls after a user withdraws consent or asks for deletion (R13).
  # Minimal until the consent slice adds the consents table and fills it in.
  class Ledger
    def self.withdrawn?(_user_id)
      false
    end
  end
end
