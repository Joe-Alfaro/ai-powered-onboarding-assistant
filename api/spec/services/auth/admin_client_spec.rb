require "rails_helper"

RSpec.describe Auth::AdminClient do
  subject(:client) { described_class.default }

  let(:users_url) { "#{ENV.fetch("SUPABASE_URL")}/auth/v1/admin/users" }

  describe "#create_user" do
    def create
      client.create_user(email: "demo@example.com", password: "demo-password")
    end

    it "creates a confirmed user with the service role key" do
      stub = stub_request(:post, users_url)
        .with(body: { email: "demo@example.com", password: "demo-password", email_confirm: true }.to_json,
              headers: { "apikey" => ENV.fetch("SUPABASE_SERVICE_ROLE_KEY") })
        .to_return(status: 200, body: "{}")

      expect(create).to eq(:created)
      expect(stub).to have_been_requested
    end

    it "reports an existing user from an older Auth server that only says so in the message" do
      stub_request(:post, users_url)
        .to_return(status: 422, body: { msg: "A user with this email address has already been registered" }.to_json)

      expect(create).to eq(:exists)
    end

    it "raises on any other refusal" do
      stub_request(:post, users_url).to_return(status: 422, body: "not json")

      expect { create }.to raise_error(described_class::Error, /HTTP 422/)
    end

    it "raises when Auth can't be reached" do
      stub_request(:post, users_url).to_raise(Errno::ECONNREFUSED)

      expect { create }.to raise_error(described_class::Error, /could not be reached/)
    end
  end
end
