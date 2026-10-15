# Typed-in identity, for a user who skips the upload or whose upload couldn't be read (R10). No
# image is involved, so no consent record is needed.
class Onboarding::IdentitiesController < ApplicationController
  def create
    onboarding = Documents::Lifecycle.new(user_id: current_user_id).enter_manually(params.permit(*Onboarding::IDENTITY_FIELDS))
    render json: { onboarding: onboarding.identity }
  end
end
