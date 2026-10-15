# GET /health (R31): public, and 503 only when the database is down.
class HealthController < ApplicationController
  skip_before_action :authenticate!

  def show
    result = Health::Check.new(probes: Health::Check.probes).call
    render json: result, status: result[:status] == "down" ? :service_unavailable : :ok
  end
end
