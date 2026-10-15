require "rails_helper"

# R14: MAX_UPLOAD_MB is enforced before the body is read into memory. These examples call the
# whole Rack app with a request body that is generated lazily and counts what is read from it, so
# a server that buffers the body first (Rack::Test's in-memory bodies can't show this) fails.
module DocumentsUploadLimitSpec
  # A multipart body of `size` bytes made up on demand. It records how many bytes the app read.
  class CountingBody
    attr_reader :bytes_read

    def initialize(head, size)
      @head = head.b
      @size = size
      @bytes_read = 0
    end

    def read(length = nil, buffer = nil)
      remaining = @size - @bytes_read
      return (length.nil? || length.zero? ? "".b : nil) if remaining <= 0

      count = length.nil? ? remaining : [ length, remaining ].min
      chunk = chunk_at(@bytes_read, count)
      @bytes_read += count
      buffer ? buffer.replace(chunk) : chunk
    end

    def gets
      read(16 * 1024)
    end

    def each
      while (chunk = read(16 * 1024))
        yield chunk
      end
    end

    def rewind
      @bytes_read = 0
    end

    def close; end

    private

    def chunk_at(offset, count)
      head = offset < @head.bytesize ? @head.byteslice(offset, count) : "".b
      head + ("\0".b * (count - head.bytesize))
    end
  end
end

RSpec.describe "POST /documents body size limit", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let!(:storage) { stub_storage }
  let(:limit_bytes) { 10 * 1024 * 1024 }
  let(:boundary) { "----spec-boundary" }

  def oversized_body(size)
    head = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"big.jpg\"\r\n" \
           "Content-Type: image/jpeg\r\n\r\n".b + File.binread(document_fixture("id.jpg"))
    DocumentsUploadLimitSpec::CountingBody.new(head, size)
  end

  def call_app(body, headers)
    env = Rack::MockRequest.env_for(
      "/documents",
      :method => "POST",
      :input => body,
      "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}",
      "HTTP_AUTHORIZATION" => "Bearer #{supabase_token(sub: user_id)}"
    ).merge(headers)
    env["rack.input"] = body # env_for may wrap the input; give the app the counting stream itself
    status, _headers, response_body = Rails.application.call(env)
    chunks = []
    response_body.each { |chunk| chunks << chunk }
    response_body.close if response_body.respond_to?(:close)
    [ status, (JSON.parse(chunks.join) rescue { "unparsed" => chunks.join.truncate(200) }) ]
  end

  before { grant_consent(user_id) }

  it "rejects a declared Content-Length over the limit with 413 without reading the body" do
    extractor = stub_extractor
    body = oversized_body(50 * 1024 * 1024)

    status, json = call_app(body, "CONTENT_LENGTH" => (50 * 1024 * 1024).to_s)

    expect(status).to eq(413)
    expect(json.dig("error", "code")).to eq("file_too_large")
    expect(json.dig("error", "message")).to include("10 MB")
    expect(body.bytes_read).to be < 1024 * 1024
    expect(extractor.called?).to be(false)
    expect(storage.requests).to be_empty
    expect(DocumentUpload.count).to eq(0)
  end

  it "stops reading a body with no Content-Length soon after it passes the limit (413)" do
    extractor = stub_extractor
    body = oversized_body(50 * 1024 * 1024)

    status, json = call_app(body, "HTTP_TRANSFER_ENCODING" => "chunked")

    expect(status).to eq(413)
    expect(json.dig("error", "code")).to eq("file_too_large")
    expect(body.bytes_read).to be <= limit_bytes + (1024 * 1024)
    expect(extractor.called?).to be(false)
    expect(storage.requests).to be_empty
  end
end
