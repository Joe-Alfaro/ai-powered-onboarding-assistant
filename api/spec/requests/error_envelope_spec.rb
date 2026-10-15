require "rails_helper"

module ErrorEnvelopeSpec
  PERSONAL_DETAIL = "Philippa Quarrington-Sentinel 1979-04-02".freeze

  FAILURES = {
    "not_found" => -> { raise ActiveRecord::RecordNotFound },
    "parameter_missing" => -> { raise ActionController::ParameterMissing, :onboarding },
    "record_invalid" => -> { raise ActiveRecord::RecordInvalid },
    "connection_not_established" => -> { raise ActiveRecord::ConnectionNotEstablished },
    "database_connection_error" => -> { raise ActiveRecord::DatabaseConnectionError },
    "connection_pool_timeout" => -> { raise ActiveRecord::ConnectionTimeoutError },
    "real_database_down" => -> { UnreachableDatabase.connection.select_value("SELECT 1") },
    "jwks_unavailable" => -> { raise Auth::JwtVerifier::JwksUnavailable },
    "dependency_error" => lambda {
      raise ApiError.new(status: 503, code: "llm_unavailable", message: "The assistant is unavailable.",
        actions: %w[retry manual])
    },
    "unexpected" => -> { raise PERSONAL_DETAIL }
  }.freeze

  class FailuresController < ApplicationController
    def show
      FAILURES.fetch(params[:kind]).call
      head :ok
    end
  end
end

# R30: one rescue_from layer maps known failures to the JSON error envelope with a 4xx or 503,
# and nothing renders a default error page.
RSpec.describe "Error envelope", type: :request do
  let(:headers) { auth_headers(SecureRandom.uuid) }

  before do
    unreachable_database
    draw_spec_routes { get "/spec/failures/:kind", to: "error_envelope_spec/failures#show" }
  end

  def fail_with(kind)
    get "/spec/failures/#{kind}", headers: headers
  end

  def error
    response.parsed_body.fetch("error")
  end

  shared_examples "an error envelope" do |kind, status, code|
    it "maps #{kind} to #{status} #{code}" do
      fail_with(kind)

      expect(response).to have_http_status(status)
      expect(response.media_type).to eq("application/json")
      expect(error).to include("code" => code, "message" => a_kind_of(String), "actions" => a_kind_of(Array))
      expect(error["message"]).to be_present
    end
  end

  describe "R30: known failures map to the envelope with a 4xx" do
    include_examples "an error envelope", "not_found", 404, "not_found"
    include_examples "an error envelope", "parameter_missing", 400, "invalid_request"
    include_examples "an error envelope", "record_invalid", 422, "validation_failed"
  end

  describe "R30: database unavailable gives a 503 envelope, never a default error page" do
    include_examples "an error envelope", "connection_not_established", 503, "database_unavailable"
    include_examples "an error envelope", "database_connection_error", 503, "database_unavailable"
    include_examples "an error envelope", "connection_pool_timeout", 503, "database_unavailable"
    include_examples "an error envelope", "real_database_down", 503, "database_unavailable"

    it "offers a retry action when the database is down" do
      fail_with("real_database_down")

      expect(error["actions"]).to include("retry")
    end
  end

  describe "R30: other dependency failures map to a 503 envelope" do
    include_examples "an error envelope", "jwks_unavailable", 503, "auth_unavailable"

    it "renders an ApiError raised by a dependency with its own status, code, message and actions" do
      fail_with("dependency_error")

      expect(response).to have_http_status(:service_unavailable)
      expect(error).to eq("code" => "llm_unavailable", "message" => "The assistant is unavailable.",
        "actions" => %w[retry manual])
    end
  end

  describe "R30: an unexpected error still gets the envelope, without leaking its message" do
    include_examples "an error envelope", "unexpected", 500, "internal_error"

    it "doesn't put the exception message in the response" do
      fail_with("unexpected")

      expect(response.body).not_to include("Sentinel")
    end
  end
end

RSpec.describe "Unknown routes", type: :request do
  it "R30: returns a 404 JSON envelope instead of a default error page" do
    get "/no-such-route-anywhere"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body.dig("error", "code")).to eq("not_found")
  end
end
