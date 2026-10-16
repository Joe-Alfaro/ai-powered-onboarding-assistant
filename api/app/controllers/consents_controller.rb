# Records the signed-in user's consent to process an ID image, with the consent text version
# they were shown (R12), and withdraws it, hard-deleting what it covered (R13).
class ConsentsController < ApplicationController
  def create
    consent = Consent::Ledger.grant!(user_id: current_user_id, text_version: params.require(:text_version))
    render json: { consent: { text_version: consent.text_version, granted_at: consent.granted_at } }, status: :created
  end

  def destroy
    Privacy::Purger.new(user_id: current_user_id).withdraw_consent
    head :no_content
  end
end
