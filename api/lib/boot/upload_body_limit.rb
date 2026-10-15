require "tempfile"

# Enforces MAX_UPLOAD_MB on POST /documents before the body is read (R14). A declared
# Content-Length over the limit is refused without reading anything. A body with no
# Content-Length (chunked) is copied to a temp file a chunk at a time and refused as soon as it
# passes the limit, so an endless or huge stream is never held in memory or read to the end.
# The limit allows for the multipart headers around the file; Uploads::Validator checks the file
# itself against the exact limit.
class UploadBodyLimit
  PATH = %r{\A/documents/?\z}
  MULTIPART_OVERHEAD_BYTES = 64 * 1024
  CHUNK_BYTES = 16 * 1024

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"].to_s.match?(PATH)

    allowed = Uploads::Validator.max_bytes + MULTIPART_OVERHEAD_BYTES
    if env["CONTENT_LENGTH"].present?
      return env["CONTENT_LENGTH"].to_i > allowed ? too_large : @app.call(env)
    end

    Tempfile.create("upload-body", binmode: true) do |spool|
      return too_large unless copy(env["rack.input"], spool, allowed)

      spool.rewind
      @app.call(env.merge("rack.input" => spool, "CONTENT_LENGTH" => spool.size.to_s))
    end
  end

  private

  # Copies at most allowed bytes; false when the input had more.
  def copy(input, spool, allowed)
    return true if input.nil?

    copied = 0
    while (chunk = input.read([ CHUNK_BYTES, allowed - copied + 1 ].min))
      break if chunk.empty?

      copied += chunk.bytesize
      return false if copied > allowed

      spool.write(chunk)
    end
    true
  end

  def too_large
    [ 413, { "content-type" => "application/json; charset=utf-8" }, [ Uploads::Validator.too_large_error.to_envelope.to_json ] ]
  end
end
