# Records the signed-in user's consent to process an ID image, with the consent text version
# they were shown (R12).
class ConsentsController < ApplicationController
  def create
    consent = Consent::Ledger.grant!(user_id: current_user_id, text_version: params.require(:text_version))
    render json: { consent: { text_version: consent.text_version, granted_at: consent.granted_at } }, status: :created
  end
end
