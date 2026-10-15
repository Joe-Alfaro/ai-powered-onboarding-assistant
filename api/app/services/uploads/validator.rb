module Uploads
  # Checks an uploaded ID image before anything stores or reads it (R14): the size limit, the
  # type by its magic bytes (never by name or declared type), and a full libvips decode that
  # rejects truncated or corrupt files. A HEIC photo is converted to JPEG so OCR and the browser
  # preview can both read it. The uploaded filename is never looked at.
  #
  # UploadBodyLimit has already refused oversized bodies before they were read; the size check
  # here covers the multipart overhead it allows for.
  class Validator
    # A checked image ready to store and read: a local path and its content type.
    Image = Data.define(:path, :content_type, :extension)

    MAGIC = {
      jpeg: "\xFF\xD8\xFF".b,
      png: "\x89PNG\r\n\x1A\n".b
    }.freeze
    HEIF_BRANDS = %w[heic heix hevc hevx heim heis mif1 msf1].freeze
    # Decompression-bomb guard: no phone camera takes a bigger picture.
    MAX_PIXELS = 100_000_000
    JPEG_QUALITY = 90

    def self.max_bytes
      max_megabytes * 1024 * 1024
    end

    def self.max_megabytes
      Integer(ENV.fetch("MAX_UPLOAD_MB", 10))
    end

    def self.too_large_error
      ApiError.new(status: 413, code: "file_too_large",
                   message: "That file is over the #{max_megabytes} MB limit. Please upload a smaller photo or enter your details by hand.",
                   actions: [ "manual_entry" ])
    end

    # Yields an Image and cleans up any converted copy after the block. Raises ApiError when the
    # upload isn't a readable JPEG, PNG or HEIC image.
    def call(file)
      raise ApiError.new(status: 400, code: "invalid_request", message: "Please attach a photo of your ID.") unless file.respond_to?(:tempfile)
      raise self.class.too_large_error if file.size > self.class.max_bytes

      path = file.tempfile.path
      format = format_of(path)
      raise unsupported unless format

      decode(path)
      return yield Image.new(path: path, content_type: "image/#{format}", extension: format == :jpeg ? "jpg" : "png") unless format == :heif

      Tempfile.create([ "upload", ".jpg" ], binmode: true) do |converted|
        convert_to_jpeg(path, converted.path)
        yield Image.new(path: converted.path, content_type: "image/jpeg", extension: "jpg")
      end
    end

    private

    def format_of(path)
      head = File.binread(path, 16).to_s.b
      return :heif if head.byteslice(4, 4) == "ftyp" && HEIF_BRANDS.include?(head.byteslice(8, 4))

      MAGIC.find { |_format, magic| head.start_with?(magic) }&.first
    end

    # Decodes every pixel, so a file that only has a valid header fails here, not inside OCR.
    def decode(path)
      image = Vips::Image.new_from_file(path, access: :sequential, fail_on: :truncated)
      raise unreadable if image.width * image.height > MAX_PIXELS

      image.avg
    rescue Vips::Error
      raise unreadable
    end

    # Metadata (location included) is dropped from the converted copy.
    def convert_to_jpeg(source, target)
      image = Vips::Image.new_from_file(source, fail_on: :truncated).autorot
      image = image.flatten(background: 255) if image.has_alpha?
      image.jpegsave(target, Q: JPEG_QUALITY, keep: :none)
    rescue Vips::Error
      raise unreadable
    end

    def unsupported
      ApiError.new(status: 415, code: "unsupported_file_type",
                   message: "That file isn't a photo we can read. Please upload a JPEG, PNG or HEIC photo of your ID.",
                   actions: [ "manual_entry" ])
    end

    def unreadable
      ApiError.new(status: 422, code: "unreadable_image",
                   message: "We couldn't open that photo. It may be damaged. Please take a new one or enter your details by hand.",
                   actions: [ "manual_entry" ])
    end
  end
end
