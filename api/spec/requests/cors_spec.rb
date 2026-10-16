require "rails_helper"

# The web app calls the API from the browser on another origin (WEB_ORIGIN, which defaults to the
# local web app in test). The bearer token travels in the Authorization header, so no cookies and
# no credentialed CORS.
RSpec.describe "CORS", type: :request do
  let(:web_origin) { ENV.fetch("WEB_ORIGIN", "http://localhost:3000").split(",").first.strip }

  def preflight(origin)
    process :options, "/onboarding", headers: {
      "Origin" => origin,
      "Access-Control-Request-Method" => "POST",
      "Access-Control-Request-Headers" => "authorization, content-type"
    }
  end

  it "allows a preflight from WEB_ORIGIN with the Authorization and Content-Type headers" do
    preflight(web_origin)

    expect(response.headers["Access-Control-Allow-Origin"]).to eq(web_origin)
    allowed = response.headers["Access-Control-Allow-Headers"].to_s.downcase.split(/,\s*/)
    expect(allowed).to include("authorization", "content-type")
    expect(response.headers["Access-Control-Allow-Methods"].to_s).to include("POST")
  end

  it "doesn't allow credentials, since the token is sent in a header" do
    preflight(web_origin)

    expect(response.headers["Access-Control-Allow-Origin"]).to eq(web_origin)
    expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
  end

  it "gives a disallowed origin no Access-Control-Allow-Origin" do
    preflight("https://elsewhere.example.test")

    expect(response.headers).not_to have_key("Access-Control-Allow-Origin")
  end

  it "adds the CORS headers to error responses" do
    get "/onboarding", headers: { "Origin" => web_origin }

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq(web_origin)
  end
end
