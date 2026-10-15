require "rails_helper"

# R15 (base): Rails parameter filtering covers personal-data, message, image, file and
# transcript fields. The full-flow log-capture test comes with the flow itself.
RSpec.describe "Parameter filtering" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }
  let(:filtered) { "[FILTERED]" }

  %w[
    name full_name first_name last_name
    date_of_birth dob
    address street_address address_line1
    message content
    image file
    transcript
  ].each do |field|
    it "R15: filters #{field}" do
      expect(filter.filter(field => "sentinel")[field]).to eq(filtered)
    end
  end

  it "R15: filters personal-data fields nested inside other params" do
    params = { "document" => { "draft_fields" => { "full_name" => "x", "date_of_birth" => "y", "address" => "z" } } }

    expect(filter.filter(params).dig("document", "draft_fields").values).to all(eq(filtered))
  end

  it "R15: filters every message in a transcript array" do
    params = { "messages" => [ { "content" => "x" }, { "content" => "y" } ] }

    expect(filter.filter(params)["messages"]).to eq(filtered).or(all(include("content" => filtered)))
  end

  it "leaves non-personal fields readable for debugging" do
    params = { "id" => "1", "slot_id" => "2", "step" => "confirm", "intent" => "ask-question" }

    expect(filter.filter(params)).to eq(params)
  end
end
