# ID image upload, the OCR draft, its preview and confirmation (R5, R10, R11, R12, R14, R17).
# Every lookup is scoped to the token's user, so another user's upload is a 404 (R19). The
# uploaded filename is never read; only the file's bytes are used (R15).
class DocumentsController < ApplicationController
  def create
    render json: { document: lifecycle.upload(params[:file]).summary }
  end

  def show
    render json: { document: lifecycle.find(params[:id]).summary }
  end

  def preview
    render json: { url: lifecycle.preview_url(params[:id]), expires_in: Documents::Lifecycle::PREVIEW_SECONDS }
  end

  def confirm
    onboarding = lifecycle.confirm(params[:id], params.permit(*Onboarding::IDENTITY_FIELDS))
    render json: { onboarding: onboarding.identity }
  end

  private
    def lifecycle
      Documents::Lifecycle.new(user_id: current_user_id)
    end
end
