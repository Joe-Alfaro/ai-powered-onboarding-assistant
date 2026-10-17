module Perf
  # R23: uploads golden-set images one at a time and times each POST /documents, which stores the
  # image, runs OCR and answers with the extracted fields in the same request. Grants consent
  # first, since an upload needs it. The uploads stay pending and are purged with the rest.
  class OcrTiming
    class Error < StandardError; end

    CONSENT_TEXT_VERSION = "2026-10-15".freeze
    CONTENT_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg" }.freeze

    def initialize(client:, golden_dir:, runs: 20)
      @client = client
      @golden_dir = Pathname(golden_dir)
      @runs = runs
    end

    def call
      consent = @client.post_json("/consents", text_version: CONSENT_TEXT_VERSION)
      raise Error, "POST /consents returned HTTP #{consent.status}" unless consent.status == 201

      images.map { |path| @client.upload("/documents", path, content_type: CONTENT_TYPES.fetch(path.extname.downcase)) }
    end

    # The extracted-fields response: 200 with a document that has its fields.
    def self.success?(reply)
      reply.status == 200 && reply.body.dig("document", "fields").is_a?(Hash)
    end

    private
      # The first `runs` images in labels.json order, cycling if the set is smaller.
      def images
        labels = JSON.parse(@golden_dir.join("labels.json").read)
        paths = labels.map { |label| @golden_dir.join(label["image"]) }
        paths.cycle.first(@runs)
      end
  end
end
