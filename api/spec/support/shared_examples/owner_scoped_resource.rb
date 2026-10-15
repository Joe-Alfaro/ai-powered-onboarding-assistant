# R19: as user A, requesting user B's record by ID returns 403 or 404.
#
# Use in a request spec for every endpoint that loads a user's record by ID:
#
#   it_behaves_like "an owner-scoped resource" do
#     let(:owner_id) { SecureRandom.uuid }
#     let(:path) { "/bookings/#{create_booking(user_id: owner_id).id}" }
#   end
#
# Pass `method: :patch` (and `let(:params)`) for non-GET endpoints.
RSpec.shared_examples "an owner-scoped resource" do |method: :get|
  let(:intruder_id) { SecureRandom.uuid }
  let(:params) { {} }
  # Rails sends a GET with `as: :json` and params as a POST, so only encode non-GET bodies.
  let(:encoding) { method == :get ? nil : :json }

  it "returns 403 or 404 when another user requests it by ID" do
    public_send(method, path, params: params, headers: auth_headers(intruder_id), as: encoding)

    expect(response.status).to be_in([ 403, 404 ])
    expect(response.parsed_body.dig("error", "code")).to be_present
  end

  it "ignores a user ID supplied in the request" do
    public_send(method, path, params: params.merge(user_id: owner_id),
      headers: auth_headers(intruder_id).merge("X-User-Id" => owner_id), as: encoding)

    expect(response.status).to be_in([ 403, 404 ])
  end

  it "serves the record to its owner" do
    public_send(method, path, params: params, headers: auth_headers(owner_id), as: encoding)

    expect(response.status).to be_between(200, 299)
  end
end
