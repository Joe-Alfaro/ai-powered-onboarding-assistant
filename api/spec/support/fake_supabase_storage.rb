# An in-memory Supabase Storage bucket served at the HTTP boundary with WebMock, so specs can
# check what the app stored, signed and deleted without a real Storage server. It follows the
# Storage REST API: upload with POST (or PUT) /object/<bucket>/<key>, delete with
# DELETE /object/<bucket>/<key> or DELETE /object/<bucket> with `prefixes`, sign with
# POST /object/sign/<bucket>/<key> and `expiresIn`, and look up with HEAD /object/<bucket>/<key>
# or GET /object/info/<bucket>/<key>. Every call needs the service role key; the bucket is private,
# so public URLs never resolve.
class FakeSupabaseStorage
  StoredObject = Data.define(:body, :content_type)
  Request = Data.define(:method, :path, :body)

  BASE_URL = "#{ENV.fetch("SUPABASE_URL")}/storage/v1".freeze

  attr_reader :bucket, :objects, :requests, :signed

  def initialize(bucket: ENV.fetch("STORAGE_BUCKET"), service_key: ENV.fetch("SUPABASE_SERVICE_ROLE_KEY"))
    @bucket = bucket
    @service_key = service_key
    @objects = {}
    @requests = []
    @signed = []
  end

  def install
    WebMock.stub_request(:any, %r{\A#{Regexp.escape(BASE_URL)}/}).to_return { |request| handle(request) }
    self
  end

  def keys
    objects.keys
  end

  def object?(key)
    objects.key?(key)
  end

  # What a Storage lookup reports for the key right now, the way an operator would check it.
  def exists?(key)
    object?(key)
  end

  def uploads
    requests.select { |request| %w[POST PUT].include?(request.method) && request.path.start_with?("/object/#{bucket}/") }
  end

  private

  def handle(request)
    path = URI(request.uri.to_s).path.delete_prefix("/storage/v1")
    method = request.method.to_s.upcase
    requests << Request.new(method: method, path: path, body: request.body)
    return json(400, statusCode: "403", error: "Unauthorized", message: "Invalid signature") unless authorized?(request)

    route(method, path, request)
  end

  def route(method, path, request)
    b = Regexp.escape(bucket)
    write = %w[POST PUT].include?(method)
    if write && (match = path.match(%r{\A/object/sign/#{b}/(.+)\z})) then sign(match[1], request)
    elsif write && (match = path.match(%r{\A/object/#{b}/(.+)\z})) then store(match[1], request)
    elsif method == "DELETE" && path.match?(%r{\A/object/#{b}/?\z})
      delete_many(JSON.parse(request.body.to_s).fetch("prefixes", []))
    elsif method == "DELETE" && (match = path.match(%r{\A/object/#{b}/(.+)\z})) then delete_one(match[1])
    elsif %w[HEAD GET].include?(method) && (match = path.match(%r{\A/object/(?:info/|authenticated/)?#{b}/(.+)\z}))
      lookup(match[1], method)
    else not_found
    end
  end

  def authorized?(request)
    request.headers["Authorization"] == "Bearer #{@service_key}"
  end

  def store(key, request)
    key = CGI.unescape(key)
    objects[key] = StoredObject.new(body: request.body.to_s.b, content_type: request.headers["Content-Type"])
    json(200, Key: "#{bucket}/#{key}", Id: SecureRandom.uuid)
  end

  def sign(key, request)
    key = CGI.unescape(key)
    return not_found unless object?(key)

    expires_in = JSON.parse(request.body.to_s)["expiresIn"]
    signed << { key: key, expires_in: expires_in }
    json(200, signedURL: "/object/sign/#{bucket}/#{key}?token=signed-#{SecureRandom.hex(8)}")
  end

  def delete_one(key)
    key = CGI.unescape(key)
    return not_found unless objects.delete(key)

    json(200, message: "Successfully deleted")
  end

  def delete_many(prefixes)
    deleted = prefixes.filter_map { |key| key if objects.delete(key) }
    json(200, deleted.map { |key| { name: key, bucket_id: bucket } })
  end

  def lookup(key, method)
    stored = objects[CGI.unescape(key)]
    return not_found if stored.nil?
    return { status: 200, headers: { "Content-Type" => stored.content_type.to_s } } if method == "HEAD"

    { status: 200, body: stored.body, headers: { "Content-Type" => stored.content_type.to_s } }
  end

  # Storage reports a missing object as a 400 whose body carries statusCode "404".
  def not_found
    json(400, statusCode: "404", error: "not_found", message: "Object not found")
  end

  def json(status, body = nil, **fields)
    { status: status, body: JSON.generate(body || fields), headers: { "Content-Type" => "application/json" } }
  end
end
