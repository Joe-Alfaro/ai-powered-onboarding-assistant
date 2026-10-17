# The signed-in user's bookings (R6, R7, R8, R36). Every lookup is scoped to the token's user, so
# another user's booking ID is a 404 (R19). Changes go through Scheduling::Booker, and its
# outcomes map to statuses here. The request's Lograge line is the booking timing record (R24).
class BookingsController < ApplicationController
  # No actions: the envelope vocabulary is only `retry` and `manual_entry`, and neither fits. The
  # web app handles these by code.
  ERRORS = {
    not_found: [ 404, "not_found", "We couldn't find that." ],
    slot_taken: [ 409, "slot_taken", "That slot is already booked. Please pick another time." ],
    booking_exists: [ 409, "booking_exists", "You already have a booking. Reschedule or cancel it instead." ],
    slot_in_past: [ 422, "slot_in_past", "That time has already passed. Please pick another time." ]
  }.freeze

  def index
    bookings = own_bookings.active.includes(:slot).order("slots.starts_at")
    render json: { bookings: bookings.map(&:summary) }
  end

  def show
    render json: { booking: own_bookings.find(params[:id]).summary }
  end

  def create
    respond_with booker.book(slot_id: params.require(:slot_id)), status: :created
  end

  def update
    respond_with booker.reschedule(booking_id: params[:id], slot_id: params.require(:slot_id))
  end

  def destroy
    respond_with booker.cancel(booking_id: params[:id])
  end

  private
    def own_bookings
      Booking.where(user_id: current_user_id)
    end

    def booker
      Scheduling::Booker.new(user_id: current_user_id)
    end

    def respond_with(result, status: :ok)
      raise booking_error(result.outcome) unless result.success?

      render json: { booking: result.booking.summary }, status: status
    end

    def booking_error(outcome)
      status, code, message = ERRORS.fetch(outcome)
      ApiError.new(status: status, code: code, message: message)
    end
end
