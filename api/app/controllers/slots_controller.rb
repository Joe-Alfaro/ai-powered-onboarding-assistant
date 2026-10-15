# GET /slots (R6): open future slots, soonest first, times in ISO-8601 UTC (R37).
class SlotsController < ApplicationController
  def index
    render json: { slots: Slot.open.map(&:summary) }
  end
end
