module Admin
  # Slot management (R19): admin only, and every access is audited by `require_admin!`.
  class SlotsController < ApplicationController
    before_action :require_admin!

    def create
      slot = Slot.create!(params.permit(:starts_at, :ends_at))
      render json: { slot: slot.summary }, status: :created
    end

    # A slot with an active booking stays. Its cancelled bookings go with it. The row lock blocks
    # a booking from landing between the check and the delete.
    def destroy
      Slot.transaction do
        slot = Slot.lock.find(params[:id])
        raise slot_booked if slot.bookings.active.exists?

        Booking.where(slot_id: slot.id).delete_all
        slot.destroy!
      end
      head :no_content
    end

    private
      def slot_booked
        ApiError.new(status: 409, code: "slot_booked", message: "That slot has a booking, so it can't be removed.")
      end
  end
end
