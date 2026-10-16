require "rails_helper"

# R15 and R20 across the whole API flow: sign in, chat, consent, upload a real card through real
# OCR, confirm edited values, the manual-entry path, book, reschedule (by API and by chat), a
# forced LLM 503 and the upload purge job. Every value is distinctive, so finding one in the logs
# or in an LLM payload means it leaked.
#
# The LLM is a FakeLlmAdapter behind Llm::Client.from_env, except for one message that goes
# through the real Anthropic adapter to a stubbed 503 whose body echoes the request back.
#
# Backend logs are captured at the production level (info) from Rails.logger, which Lograge,
# ActiveJob and the app all write to, plus anything written to $stdout or $stderr. Frontend log
# output is covered by ESLint no-console and the later Playwright slice, not here.
module PrivacyFlowSpec
  # What the user confirms after editing the OCR draft.
  CONFIRMED = { full_name: "Zyxquorth Vellanby", date_of_birth: "1953-07-29",
                address: "4418 Quibblethorn Crescent, Marrowdale" }.freeze
  # What a second user types in on the manual-entry path.
  MANUAL = { full_name: "Pellucida Marchbanks-Oyelaran", date_of_birth: "1948-02-11",
             address: "61 Wrenfallow Close, Druncastle" }.freeze
  # Printed on spec/fixtures/files/privacy/distinctive_id.jpg, which OCR reads into the draft.
  CARD_VALUES = [ "Orvande", "Kestrelmoor", "Bramblewick", "Hollowmere", "08/19/1962", "1962-08-19" ].freeze
  FILENAME = "zyxquorth-passport-scan-88213.jpg".freeze
  CHAT_SENTENCE = "My parrot Florentijn knocked the gramophone off the mantelpiece again".freeze
  DRAFT_MARKER = "PRIVACY-DRAFT-6083".freeze
  REPLY_MARKER = "VORPAL-REPLY-5521".freeze

  # Every way the flow writes the two dates of birth.
  DATE_FORMS = [ "1953-07-29", "07/29/1953", "7/29/1953", "29/07/1953", "July 29, 1953", "29 July 1953",
                 "1948-02-11", "02/11/1948", "2/11/1948", "11/02/1948", "February 11, 1948", "11 February 1948" ].freeze

  # The identity sentences a user types into chat once their identity is on record.
  CONFIRMED_SENTENCE = "Just so you know, I'm Zyxquorth Vellanby, born 29 July 1953, and I live at " \
                       "4418 Quibblethorn Crescent, Marrowdale.".freeze
  MANUAL_SENTENCE = "For the record I'm Pellucida Marchbanks-Oyelaran, born 02/11/1948, at " \
                    "61 Wrenfallow Close, Druncastle.".freeze

  Run = Data.define(:logs, :fake_payloads, :sent_bodies, :debug_outputs, :user_id, :manual_user_id,
                    :document_id, :storage_keys, :image_bytes)

  # The flow runs real OCR several times, so the first example runs it (inside its own transaction
  # and stubs) and the rest read the same captured, plain-data result.
  class << self
    attr_accessor :cached_run
  end
end

RSpec.describe "Privacy across the full flow (R15, R20)", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let(:manual_user_id) { SecureRandom.uuid }
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/privacy/distinctive_id.jpg").to_s }
  let(:fake_llm) { FakeLlmAdapter.new.always_respond_with(llm_output("ask-question", reply: "Happy to help. #{PrivacyFlowSpec::REPLY_MARKER}")) }
  let(:doc_path) { Rails.root.join("../docs/data-to-llm.md") }
  let!(:storage) { stub_storage }
  let(:run) { PrivacyFlowSpec.cached_run ||= run_full_flow }

  def chat(user, message, **extra)
    post "/chat/messages", params: { message: message, **extra }, headers: auth_headers(user), as: :json
  end

  def expect_status(status)
    expect(response).to have_http_status(status), "#{request.method} #{request.path}: #{response.body[0, 300]}"
  end

  # Runs the block with Rails.logger broadcasting to an info-level sink and $stdout and $stderr
  # redirected, and returns everything written.
  def capture_backend_output
    out = StringIO.new
    err = StringIO.new
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = out
    $stderr = err
    logs = capture_logs { yield }
    [ logs, out.string, err.string ].join("\n")
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  # Records the debug output of every Net::HTTP connection that sends a request.
  def watch_http_debug_output(outputs)
    allow_any_instance_of(Net::HTTP).to receive(:request).and_wrap_original do |original, *args, &block|
      outputs << original.receiver.instance_variable_get(:@debug_output)
      original.call(*args, &block)
    end
  end

  def run_full_flow
    slots = Array.new(3) { |index| create_slot(starts_at: (index + 2).days.from_now.utc.change(min: 0, sec: 0)) }
    sent_bodies = []
    debug_outputs = []
    client = Llm::Client.new(primary: fake_llm)
    allow(Llm::Client).to receive(:from_env) { client }
    watch_http_debug_output(debug_outputs)
    stub_request(:post, LlmHelpers::ANTHROPIC_URL).to_return do |request|
      sent_bodies << request.body
      # A provider that echoes the request in its error body, as some do.
      { status: 503, body: { error: { message: "overloaded", request: request.body } }.to_json,
        headers: { "Content-Type" => "application/json" } }
    end
    document_id = nil

    logs = capture_backend_output do
      # Sign in: the token is all the API needs.
      get "/bookings", headers: auth_headers(user_id)
      expect_status(:ok)

      # Several chat turns before any identity is on record.
      chat(user_id, "Hi there. #{PrivacyFlowSpec::CHAT_SENTENCE}.")
      expect_status(:ok)
      fake_llm.respond_with(llm_output("provide-details", reply: "Thanks. #{PrivacyFlowSpec::REPLY_MARKER}",
        fields: { "reason" => "#{PrivacyFlowSpec::DRAFT_MARKER} trouble sleeping", "urgency" => "medium" }))
      chat(user_id, "I've had trouble sleeping for months, it's fairly urgent.")
      expect_status(:ok)

      # Consent, then the real card through real OCR, uploaded under a distinctive filename.
      post "/consents", params: { text_version: DocumentHelpers::CONSENT_TEXT_VERSION }, headers: auth_headers(user_id)
      expect_status(:created)
      post_document(user_id, upload_file(fixture_path, filename: PrivacyFlowSpec::FILENAME))
      expect_status(:ok)
      document_id = document_body["id"]
      get "/documents/#{document_id}", headers: auth_headers(user_id)
      expect_status(:ok)
      get "/documents/#{document_id}/preview", headers: auth_headers(user_id)
      expect_status(:ok)

      # Confirm with every value edited, then mention them in chat.
      post "/documents/#{document_id}/confirm", params: PrivacyFlowSpec::CONFIRMED, headers: auth_headers(user_id)
      expect_status(:ok)
      fake_llm.respond_with(llm_output("provide-details", reply: "Noted. #{PrivacyFlowSpec::REPLY_MARKER}",
        fields: { "notes" => "Lives at 4418 Quibblethorn Crescent, Marrowdale", "preferred_window" => "mornings" }))
      chat(user_id, PrivacyFlowSpec::CONFIRMED_SENTENCE)
      expect_status(:ok)

      # The LLM error path: this message goes through the real adapter to a 503.
      client = Llm::Client.new(primary: Llm::Adapters::Anthropic.new(api_key: "test-claude-key", model: "claude-test"))
      chat(user_id, "Is Zyxquorth Vellanby's appointment still on? #{PrivacyFlowSpec::CHAT_SENTENCE}")
      expect_status(:service_unavailable)
      client = Llm::Client.new(primary: fake_llm)

      # Book, reschedule through the API, then reschedule through chat.
      post "/bookings", params: { slot_id: slots[0].id }, headers: auth_headers(user_id)
      expect_status(:created)
      booking_id = response.parsed_body.dig("booking", "id")
      patch "/bookings/#{booking_id}", params: { slot_id: slots[1].id }, headers: auth_headers(user_id)
      expect_status(:ok)
      fake_llm.respond_with(llm_output("request-reschedule", reply: "Sure. #{PrivacyFlowSpec::REPLY_MARKER}"))
      chat(user_id, "Please move Zyxquorth's appointment to the slot I picked.", booking_id: booking_id, slot_id: slots[2].id)
      expect_status(:ok)

      # A second upload left unconfirmed, then purged by the job once it expires.
      post_document(user_id, upload_file(fixture_path, filename: PrivacyFlowSpec::FILENAME))
      expect_status(:ok)
      travel(DocumentUpload::TTL + 1.minute) { Documents::PurgeExpiredUploadsJob.perform_now }

      # The manual-entry path: no consent, so the upload is refused and the user types it in.
      post_document(manual_user_id, upload_file(fixture_path, filename: PrivacyFlowSpec::FILENAME))
      expect_status(:forbidden)
      post "/onboarding/identity", params: PrivacyFlowSpec::MANUAL, headers: auth_headers(manual_user_id)
      expect_status(:ok)
      chat(manual_user_id, PrivacyFlowSpec::MANUAL_SENTENCE)
      expect_status(:ok)
      chat(manual_user_id, "What happens after onboarding? #{PrivacyFlowSpec::CHAT_SENTENCE}")
      expect_status(:ok)
    end

    PrivacyFlowSpec::Run.new(logs: logs, fake_payloads: fake_llm.payloads, sent_bodies: sent_bodies,
                             debug_outputs: debug_outputs, user_id: user_id, manual_user_id: manual_user_id,
                             document_id: document_id, storage_keys: storage.uploads.map(&:path),
                             image_bytes: File.binread(fixture_path))
  end

  # Every distinctive value the flow handles, as case-insensitive patterns, keyed for messages.
  def personal_values
    identity = (PrivacyFlowSpec::CONFIRMED.values + PrivacyFlowSpec::MANUAL.values)
    words = %w[Zyxquorth Vellanby Quibblethorn Marrowdale Pellucida Marchbanks Oyelaran Wrenfallow Druncastle]
    (identity + words + PrivacyFlowSpec::DATE_FORMS + PrivacyFlowSpec::CARD_VALUES +
      [ PrivacyFlowSpec::FILENAME, "zyxquorth-passport-scan", "Florentijn", "gramophone", PrivacyFlowSpec::CHAT_SENTENCE,
        PrivacyFlowSpec::DRAFT_MARKER, PrivacyFlowSpec::REPLY_MARKER, "trouble sleeping" ]).uniq
  end

  # Slices of the image as raw bytes, Base64 and hex, from the start, middle and end.
  def image_fragments(bytes)
    [ 0, bytes.bytesize / 2, bytes.bytesize - 48 ].flat_map do |offset|
      slice = bytes.byteslice(offset, 48)
      [ slice, Base64.strict_encode64(slice), slice.unpack1("H*") ]
    end + [ "data:image/" ]
  end

  # Lines of the system prompt long enough to be unmistakable.
  def prompt_fragments
    Chat::Prompt.base_system.lines.map(&:strip).select { |line| line.length >= 40 }
  end

  def leaks_in(text, values)
    values.select { |value| text.downcase.include?(value.downcase) }
  end

  def payload_texts(run)
    run.fake_payloads.map { |payload| ([ payload.system ] + payload.messages.map { |message| message[:content] }).join("\n") } +
      run.sent_bodies.map(&:to_s)
  end

  describe "R15: no personal data in logs" do
    it "R15 automated full-flow test: none of the distinctive values appear in the captured backend log output" do
      expect(log_lines(run.logs)).not_to be_empty
      expect(run.logs).to include("/chat/messages", "/documents", "/bookings", "/onboarding/identity")

      expect(leaks_in(run.logs, personal_values)).to eq([])
    end

    it "R15: logs never contain image data, in raw, Base64 or hex form" do
      leaked = image_fragments(run.image_bytes).select { |fragment| run.logs.b.include?(fragment.b) }

      expect(leaked).to be_empty, "#{leaked.size} image fragment(s) found in the logs"
    end

    it "R15: logs never contain the uploaded filename or chat message text" do
      expect(run.logs).not_to include(PrivacyFlowSpec::FILENAME)
      expect(run.logs).not_to include("zyxquorth-passport-scan")
      expect(run.logs).not_to include("Florentijn")
      expect(run.logs).not_to include("I've had trouble sleeping")
      expect(run.logs).not_to include(PrivacyFlowSpec::REPLY_MARKER)
    end

    it "R15: logs never contain the LLM prompt text" do
      expect(prompt_fragments).not_to be_empty
      expect(leaks_in(run.logs, prompt_fragments)).to eq([])
    end

    it "R15 error traces: the forced LLM 503 is logged by class and code only, without the echoed payload" do
      error_lines = log_lines(run.logs).select { |line| line.include?("Llm::ServerError") }

      expect(error_lines.size).to eq(1)
      expect(error_lines.first).to include("llm_server_error")
      expect(error_lines.first).not_to include("overloaded")
      expect(leaks_in(error_lines.first, personal_values + prompt_fragments)).to eq([])
    end

    it "R15 job logs: the upload purge job runs inside the capture and logs no personal data" do
      job_lines = log_lines(run.logs).select { |line| line.include?("PurgeExpiredUploadsJob") }

      expect(job_lines).not_to be_empty
      expect(leaks_in(job_lines.join("\n"), personal_values)).to eq([])
    end

    it "R15: LLM client debug logging is off for every provider request" do
      expect(run.sent_bodies.size).to eq(1)
      expect(run.debug_outputs).not_to be_empty
      expect(run.debug_outputs).to all(be_nil)
    end

    it "R15: production logs at info, the level these captures use, so SQL and debug lines are off" do
      production = Rails.root.join("config/environments/production.rb").read

      expect(production).to match(/config\.log_level\s*=\s*ENV\.fetch\("RAILS_LOG_LEVEL",\s*"info"\)/)
    end
  end

  describe "R20: data sent to AI providers is minimal and documented" do
    def documented_fields
      section = doc_path.read[/^## Fields sent\s*$(.*?)(?=^## |\z)/m, 1]
      expect(section).to be_present, "docs/data-to-llm.md has no \"## Fields sent\" section"
      section.scan(/^\|\s*`([a-z_]+)`\s*\|/).flatten.sort
    end

    def personal_data_fields(run)
      {
        "full_name" => [ /zyxquorth/i, /vellanby/i, /pellucida/i, /marchbanks/i, /oyelaran/i ],
        "date_of_birth" => PrivacyFlowSpec::DATE_FORMS.map { |form| /#{Regexp.escape(form)}/i },
        "address" => [ /quibblethorn/i, /marrowdale/i, /wrenfallow/i, /druncastle/i ],
        "email" => [ /#{Regexp.escape(run.user_id)}@example\.test/i, /#{Regexp.escape(run.manual_user_id)}@example\.test/i ],
        "user_id" => [ /#{Regexp.escape(run.user_id)}/i, /#{Regexp.escape(run.manual_user_id)}/i ],
        "message_text" => [ /Florentijn/ ],
        "assessment_draft" => [ /#{PrivacyFlowSpec::DRAFT_MARKER}/ ]
      }
    end

    def fields_found_in(text, run)
      personal_data_fields(run).select { |_field, patterns| patterns.any? { |pattern| text.match?(pattern) } }.keys.sort
    end

    # The payloads sent after each user's identity was confirmed.
    def payloads_after_identity(run)
      run.fake_payloads.select do |payload|
        payload.messages.any? { |message| message[:content].include?("[NAME]") || message[:content].match?(/zyxquorth|pellucida/i) }
      end
    end

    it "R20 gotcha: once identity is confirmed from the OCR draft, a chat message typing it gets placeholders in the outgoing payload" do
      payload = run.fake_payloads.find { |candidate| candidate.messages.last[:content].include?("I live at") }
      expect(payload).to be_present, "the confirmed-identity message never reached the LLM"
      sent = payload.messages.last[:content]

      expect(sent).to include("[NAME]", "[DATE_OF_BIRTH]", "[ADDRESS]")
      expect(leaks_in(sent, %w[Zyxquorth Vellanby 1953 Quibblethorn Marrowdale])).to eq([])
    end

    it "R20 gotcha: once identity is typed in by hand, a chat message typing it gets placeholders in the outgoing payload" do
      payload = run.fake_payloads.find { |candidate| candidate.messages.last[:content].start_with?("For the record") }
      expect(payload).to be_present, "the manual-identity message never reached the LLM"
      sent = payload.messages.last[:content]

      expect(sent).to include("[NAME]", "[DATE_OF_BIRTH]", "[ADDRESS]")
      expect(leaks_in(sent, %w[Pellucida Marchbanks Oyelaran 1948 Wrenfallow Druncastle])).to eq([])
    end

    it "R20 gotcha: identity stays redacted in the chat history and draft of every later payload" do
      later = payloads_after_identity(run)
      expect(later.size).to be >= 3

      later.each do |payload|
        text = ([ payload.system ] + payload.messages.map { |message| message[:content] }).join("\n")
        expect(leaks_in(text, %w[Zyxquorth Vellanby Quibblethorn Marrowdale Pellucida Wrenfallow])).to eq([])
      end
    end

    it "R20 gotcha: the request body the real adapter sent on the 503 path carries placeholders, not the identity" do
      body = run.sent_bodies.first.to_s
      expect(body).to include("Florentijn") # the current message did go out

      expect(body).to include("[NAME]")
      expect(leaks_in(body, %w[Zyxquorth Vellanby 1953 Quibblethorn Marrowdale])).to eq([])
    end

    it "R20 contract: the full-flow payload's personal-data fields match docs/data-to-llm.md exactly" do
      last_payload = payloads_after_identity(run).select { |payload| payload.system.include?(PrivacyFlowSpec::DRAFT_MARKER) }.last
      expect(last_payload).to be_present
      text = ([ last_payload.system ] + last_payload.messages.map { |message| message[:content] }).join("\n")

      expect(fields_found_in(text, run)).to eq(documented_fields)
    end

    it "R20 contract: across every payload in the flow, only documented personal-data fields are sent" do
      found = payload_texts(run).flat_map { |text| fields_found_in(text, run) }.uniq.sort

      expect(found - documented_fields).to eq([])
    end

    it "R20: no image bytes or document data reach the LLM anywhere in the flow" do
      texts = payload_texts(run)
      expect(texts).not_to be_empty
      document_data = PrivacyFlowSpec::CARD_VALUES + [ PrivacyFlowSpec::FILENAME, "zyxquorth-passport-scan", run.document_id,
                                                       "confidence", "draft_fields", "storage_key" ] +
                      run.storage_keys.map { |path| path.split("/").last }

      texts.each do |text|
        expect(text).to be_valid_encoding
        expect(leaks_in(text, document_data.compact)).to eq([])
        expect(image_fragments(run.image_bytes).select { |fragment| text.b.include?(fragment.b) }).to eq([])
      end
    end
  end
end
