require "rails_helper"
require "rake"

# Deploy readiness: a fresh deploy creates the private ID-image bucket itself (R17), with the
# service role key, and leaves an existing bucket alone.
RSpec.describe "Storage bucket setup" do
  let(:storage_url) { "#{ENV.fetch("SUPABASE_URL")}/storage/v1" }
  let(:bucket) { ENV.fetch("STORAGE_BUCKET") }
  let(:auth) { { "Authorization" => "Bearer #{ENV.fetch("SUPABASE_SERVICE_ROLE_KEY")}" } }
  let(:client) { Storage::Client.default }

  def stub_lookup(status:, body:)
    stub_request(:get, "#{storage_url}/bucket/#{bucket}").with(headers: auth)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  let!(:create) do
    stub_request(:post, "#{storage_url}/bucket").with(headers: auth).to_return(status: 200, body: { name: bucket }.to_json)
  end

  describe Storage::Client, "#ensure_bucket" do
    it "creates the bucket as private when it doesn't exist" do
      stub_lookup(status: 400, body: { statusCode: "404", error: "Bucket not found" })

      expect(client.ensure_bucket).to eq(:created)
      expect(create.with(body: hash_including("id" => bucket, "name" => bucket, "public" => false))).to have_been_requested.once
    end

    it "also treats a plain 404 as missing" do
      stub_lookup(status: 404, body: { error: "not found" })

      expect(client.ensure_bucket).to eq(:created)
    end

    it "does nothing when the private bucket already exists" do
      stub_lookup(status: 200, body: { id: bucket, name: bucket, public: false })

      expect(client.ensure_bucket).to eq(:exists)
      expect(create).not_to have_been_requested
    end

    it "makes an existing public bucket private, because ID images must never be public" do
      stub_lookup(status: 200, body: { id: bucket, name: bucket, public: true })
      update = stub_request(:put, "#{storage_url}/bucket/#{bucket}").with(headers: auth, body: hash_including("public" => false))
        .to_return(status: 200, body: { message: "Successfully updated" }.to_json)

      expect(client.ensure_bucket).to eq(:made_private)
      expect(update).to have_been_requested.once
      expect(create).not_to have_been_requested
    end

    it "counts a bucket created by a concurrent deploy as existing" do
      stub_lookup(status: 400, body: { statusCode: "404", error: "Bucket not found" })
      stub_request(:post, "#{storage_url}/bucket").to_return(status: 400, body: { statusCode: "409", error: "Duplicate" }.to_json)

      expect(client.ensure_bucket).to eq(:exists)
    end

    it "raises when Storage refuses the call" do
      stub_lookup(status: 401, body: { statusCode: "403", error: "Unauthorized" })

      expect { client.ensure_bucket }.to raise_error(Storage::Client::Error, /HTTP 401/)
    end
  end

  describe "bin/rails storage:ensure_bucket" do
    before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("storage:ensure_bucket") }

    let(:task) { Rake::Task["storage:ensure_bucket"].tap(&:reenable) }

    it "creates the bucket and says so" do
      stub_lookup(status: 400, body: { statusCode: "404", error: "Bucket not found" })

      expect { task.invoke }.to output(/#{bucket}.*created/).to_stdout
      expect(create).to have_been_requested.once
    end

    it "is a no-op when the bucket exists" do
      stub_lookup(status: 200, body: { id: bucket, name: bucket, public: false })

      expect { task.invoke }.to output(/#{bucket}.*already exists/).to_stdout
      expect(create).not_to have_been_requested
    end
  end

  describe "the container entrypoint" do
    let(:entrypoint) { Rails.root.join("bin/docker-entrypoint").read }

    it "ensures the bucket after db:prepare, before the server starts" do
      prepare = entrypoint.index("db:prepare")
      ensure_bucket = entrypoint.index("storage:ensure_bucket")

      expect(prepare).to be_present
      expect(ensure_bucket).to be_present
      expect(ensure_bucket).to be > prepare
      expect(entrypoint.index("exec")).to be > ensure_bucket
    end
  end
end
