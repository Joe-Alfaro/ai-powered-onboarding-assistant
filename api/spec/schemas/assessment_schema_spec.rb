require "rails_helper"

# R2: a committed schema defines the assessment record and its required fields.
RSpec.describe "Assessment schema (app/schemas/assessment.json)" do
  let(:complete_record) do
    { "reason" => "Trouble sleeping", "urgency" => "medium", "preferred_window" => "Weekday mornings",
      "distress" => false, "notes" => "" }
  end

  it "R2: is committed and is a valid JSON Schema" do
    expect(File).to exist(ChatHelpers::SCHEMA_PATH)
    expect(JSONSchemer.valid_schema?(assessment_schema)).to be(true)
  end

  it "R2: requires reason, urgency, preferred appointment window, distress flag and notes" do
    expect(assessment_schema["required"]).to match_array(ChatHelpers::REQUIRED_ASSESSMENT_FIELDS)
  end

  it "R2: types the distress flag as a boolean and limits urgency to a fixed set" do
    properties = assessment_schema.fetch("properties")

    expect(properties.dig("distress", "type")).to eq("boolean")
    expect(properties.dig("urgency", "enum")).to match_array(%w[low medium high])
  end

  it "R2: accepts a complete record" do
    expect(schema_errors(complete_record)).to be_empty
  end

  ChatHelpers::REQUIRED_ASSESSMENT_FIELDS.each do |field|
    it "R2: rejects a record missing #{field}" do
      expect(schema_errors(complete_record.except(field))).not_to be_empty
    end
  end

  it "R2: rejects a blank reason or preferred window, so a required field can't be saved empty" do
    expect(schema_errors(complete_record.merge("reason" => ""))).not_to be_empty
    expect(schema_errors(complete_record.merge("preferred_window" => ""))).not_to be_empty
  end

  it "R2: rejects wrong types and fields it doesn't define" do
    expect(schema_errors(complete_record.merge("distress" => "yes"))).not_to be_empty
    expect(schema_errors(complete_record.merge("urgency" => "whenever"))).not_to be_empty
    expect(schema_errors(complete_record.merge("email" => "someone@example.test"))).not_to be_empty
  end
end
