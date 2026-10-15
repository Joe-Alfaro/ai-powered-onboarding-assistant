require "rails_helper"

RSpec.describe Llm::PayloadBuilder do
  let(:identity) do
    { full_name: "Marisol Quintanilla-Ferro", date_of_birth: Date.new(1987, 3, 14), address: "42 Wallaby Way, Springfield" }
  end

  def build(turns:, identity: self.identity, assessment_draft: {})
    described_class.new(identity: identity).build(
      system: "You are an onboarding assistant.", turns: turns,
      assessment_draft: assessment_draft, response_schema: LlmHelpers::RESPONSE_SCHEMA
    )
  end

  def user_says(text, **options)
    build(turns: [ { role: "user", content: text } ], **options)
  end

  # Everything in the payload an LLM would read.
  def outgoing_text(payload)
    [ payload.system, *payload.messages.map { |message| message[:content] } ].join("\n")
  end

  it "builds an Llm::Payload with the system prompt, the turns and the response schema" do
    payload = build(turns: [ { role: "user", content: "Hello" }, { role: "assistant", content: "Hi there" } ])

    expect(payload).to be_a(Llm::Payload)
    expect(payload.system).to include("You are an onboarding assistant.")
    expect(payload.messages).to eq([ { role: "user", content: "Hello" }, { role: "assistant", content: "Hi there" } ])
    expect(payload.response_schema).to eq(LlmHelpers::RESPONSE_SCHEMA)
  end

  describe "R20: known identity values are replaced by placeholders in message text" do
    it "replaces the full name, ignoring case" do
      text = outgoing_text(user_says("Hi, I'm Marisol Quintanilla-Ferro. MARISOL QUINTANILLA-FERRO again."))

      expect(text).not_to match(/marisol|quintanilla/i)
      expect(text.scan("[NAME]").size).to eq(2)
    end

    it "replaces each part of the name on its own, as whole words only" do
      text = outgoing_text(user_says("Call me Marisol. My sister Marisola is not me."))

      expect(text).to include("Call me [NAME].")
      expect(text).to include("Marisola")
    end

    {
      "ISO" => "1987-03-14",
      "US numeric" => "03/14/1987",
      "US numeric without padding" => "3/14/1987",
      "long month first" => "March 14, 1987",
      "day first" => "14 March 1987"
    }.each do |format, written|
      it "replaces the date of birth written as #{format} (#{written})" do
        text = outgoing_text(user_says("I was born on #{written}, if that matters."))

        expect(text).not_to include(written)
        expect(text).to include("[DATE_OF_BIRTH]")
      end
    end

    it "replaces the address, ignoring case" do
      text = outgoing_text(user_says("I live at 42 wallaby way, springfield."))

      expect(text).not_to match(/wallaby/i)
      expect(text).to include("[ADDRESS]")
    end

    it "replaces the street line of the address when written alone" do
      text = outgoing_text(user_says("Send it to 42 Wallaby Way please."))

      expect(text).not_to match(/wallaby/i)
      expect(text).to include("[ADDRESS]")
    end

    it "replaces identity values in assistant turns too" do
      payload = build(turns: [
        { role: "assistant", content: "Thanks, Marisol. Is 42 Wallaby Way, Springfield still right?" },
        { role: "user", content: "Yes" }
      ])

      expect(outgoing_text(payload)).not_to match(/marisol|wallaby/i)
    end

    it "replaces identity values inside the assessment draft" do
      payload = user_says("Hello", assessment_draft: { "notes" => "Marisol was born 1987-03-14" })

      expect(outgoing_text(payload)).not_to match(/marisol|1987-03-14/i)
    end

    it "leaves text alone when no identity value is present" do
      text = outgoing_text(user_says("I feel anxious about the first session."))

      expect(text).to include("I feel anxious about the first session.")
      expect(text).not_to include("[NAME]", "[DATE_OF_BIRTH]", "[ADDRESS]")
    end

    it "skips identity values that are not known yet" do
      payload = user_says("Hi, I'm Marisol.", identity: { full_name: nil, date_of_birth: nil, address: nil })

      expect(outgoing_text(payload)).to include("Hi, I'm Marisol.")
    end
  end

  describe "R20: the assessment draft is limited to the fields the LLM is asked to fill" do
    it "includes the declared assessment fields" do
      payload = user_says("Hello", assessment_draft: { "reason" => "sleep trouble", "urgency" => "this week" })

      expect(outgoing_text(payload)).to include("sleep trouble", "this week")
    end

    it "drops draft keys the response schema does not declare" do
      payload = user_says("Hello", assessment_draft: {
        "reason" => "sleep trouble", "email" => "someone@example.test", "user_id" => "uid-5d1e0c"
      })

      expect(outgoing_text(payload)).not_to include("someone@example.test", "uid-5d1e0c")
    end
  end

  describe "R20: no code path can send image bytes to an LLM" do
    jpeg = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b
    png = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b

    {
      "JPEG bytes" => jpeg,
      "PNG bytes" => png,
      "a base64 data URI" => "look: data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB",
      "an image content block" => [ { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "AAAA" } } ],
      "an image_url content block" => [ { type: "image_url", image_url: { url: "https://example.test/id.jpg" } } ],
      "an IO object" => StringIO.new(jpeg)
    }.each do |kind, content|
      it "rejects a turn whose content is #{kind}" do
        expect { build(turns: [ { role: "user", content: content } ]) }
          .to raise_error(Llm::PayloadBuilder::DisallowedContent)
      end
    end

    it "rejects image bytes in the assessment draft" do
      expect { user_says("Hello", assessment_draft: { "notes" => jpeg }) }
        .to raise_error(Llm::PayloadBuilder::DisallowedContent)
    end

    it "rejects text that is not valid UTF-8" do
      expect { user_says("caf\xC3".dup.force_encoding("UTF-8")) }
        .to raise_error(Llm::PayloadBuilder::DisallowedContent)
    end
  end

  describe "R20: Llm::PayloadBuilder is the only way to make a payload" do
    it "does not let other code construct an Llm::Payload directly" do
      expect { Llm::Payload.new(system: "x", messages: [], response_schema: {}) }.to raise_error(NoMethodError)
    end
  end
end
