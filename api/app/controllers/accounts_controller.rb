# DELETE /account (R13): deletes the signed-in user's personal data, bookings and Auth account.
# The user comes only from the token (R19).
class AccountsController < ApplicationController
  def destroy
    Privacy::Purger.new(user_id: current_user_id).delete_account
    head :no_content
  end
end
