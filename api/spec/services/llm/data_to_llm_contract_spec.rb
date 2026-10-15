require "rails_helper"

# R20 contract: capture the request body that actually leaves for each LLM provider and check that
# the personal-data fields found in it are exactly the ones docs/data-to-llm.md lists.
#
# The document lists the fields sent in a section headed "## Fields sent", one table row per
# field, with the field ID in backticks in the first cell:
#
#   | Field | Why it is needed |
#   | --- | --- |
#   | `message_text` | ... |
#
# Field IDs are the keys of personal_data below. Every value seeded here is distinctive, so finding
# it in the outgoing body means that field was sent.
RSpec.describe "R20 data sent to LLM providers matches docs/data-to-llm.md" do
  let(:doc_path) { Rails.root.join("../docs/data-to-llm.md") }

  let(:identity) do
    {
      full_name: "Thaddeus Okonkwo-Brandvold",
      date_of_birth: Date.new(1979, 11, 23),
      address: "907 Larkspur Terrace, Fairhollow"
    }
  end

  let(:personal_data) do
    {
      "full_name" => [ /thaddeus/i, /okonkwo/i, /brandvold/i ],
      "date_of_birth" => [ /1979-11-23/, %r{11/23/1979}, /November 23, 1979/i, /23 November 1979/i ],
      "address" => [ /larkspur/i, /fairhollow/i ],
      "email" => [ /thaddeus\.contract@example\.test/i ],
      "user_id" => [ /uid-7c41e2f0/ ],
      "message_text" => [ /ZEBRA-MESSAGE-7731/ ],
      "assessment_draft" => [ /QUOKKA-DRAFT-4410/ ]
    }
  end

  def documented_fields
    expect(File).to exist(doc_path), "docs/data-to-llm.md is missing"
    section = File.read(doc_path)[/^## Fields sent\s*$(.*?)(?=^## |\z)/m, 1]
    expect(section).to be_present, "docs/data-to-llm.md has no \"## Fields sent\" section"
    section.scan(/^\|\s*`([a-z_]+)`\s*\|/).flatten.sort
  end

  # The user mentions their identity in chat, the assistant echoes it, and the draft carries fields
  # the schema does not ask for, so redaction and the allowlist are both exercised.
  def contract_payload
    build_llm_payload(
      identity: identity,
      turns: [
        { role: "user", content: "ZEBRA-MESSAGE-7731 I'm Thaddeus Okonkwo-Brandvold, born 11/23/1979, " \
                                 "at 907 Larkspur Terrace, Fairhollow." },
        { role: "assistant", content: "Thanks Thaddeus. What brings you here?" },
        { role: "user", content: "Trouble sleeping since November 23, 1979 was mentioned." }
      ],
      assessment_draft: {
        "reason" => "QUOKKA-DRAFT-4410 trouble sleeping",
        "notes" => "Lives at 907 Larkspur Terrace",
        "email" => "thaddeus.contract@example.test",
        "user_id" => "uid-7c41e2f0"
      }
    )
  end

  def string_leaves(value)
    case value
    when Hash then value.values.flat_map { |nested| string_leaves(nested) }
    when Array then value.flat_map { |nested| string_leaves(nested) }
    else [ value.to_s ]
    end
  end

  def fields_found_in(body)
    text = string_leaves(JSON.parse(body)).join("\n")
    personal_data.select { |_field, patterns| patterns.any? { |pattern| text.match?(pattern) } }.keys.sort
  end

  LlmHelpers::PROVIDER_URLS.each do |provider, url|
    it "sends #{provider} exactly the personal-data fields the document lists" do
      captured = nil
      stub_request(:post, url).to_return do |request|
        captured = request.body
        { status: 200, body: success_body_for(provider), headers: { "Content-Type" => "application/json" } }
      end

      Llm::Client.from_env(llm_env("LLM_PROVIDER" => provider, "LLM_MODEL" => "contract-model"))
        .complete(contract_payload)

      expect(captured).to be_present
      expect(fields_found_in(captured)).to eq(documented_fields)
    end
  end

  it "the document never lists an identity field the payload builder redacts" do
    expect(documented_fields & %w[full_name date_of_birth address]).to be_empty
  end
end
