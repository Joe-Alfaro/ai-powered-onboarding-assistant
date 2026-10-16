# Where the signed-in user is in the flow, for the web app's redirects and done page (R8). The step
# is worked out from the saved records, furthest point reached first, so it can't drift from them.
# Identity comes back as a status only, never its values (R17), and every read is scoped to the
# token's user (R19). The GET is read-only: a user with no records yet gets the chat step.
class OnboardingsController < ApplicationController
  def show
    onboarding = Onboarding.find_by(user_id: current_user_id)
    assessment = Assessment.find_by(user_id: current_user_id)
    confirmed_at = onboarding&.confirmed_at

    render json: {
      onboarding: {
        step: step_for(assessment:, confirmed: confirmed_at.present?),
        assessment: assessment&.data,
        identity: {
          confirmed: confirmed_at.present?,
          source: confirmed_at && onboarding.identity_source,
          confirmed_at: confirmed_at&.utc&.iso8601
        }
      }
    }
  end

  private
    def step_for(assessment:, confirmed:)
      return "done" if Booking.active.exists?(user_id: current_user_id)
      return "schedule" if confirmed
      return "identity" if assessment

      "chat"
    end
end
