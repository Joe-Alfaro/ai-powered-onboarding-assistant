require "rails_helper"

# R33: bin/gates, which the pre-push hook and the CI gates job both run, includes the env check
# and the full-history secret scan.
RSpec.describe "bin/gates" do
  let(:commands) do
    Rails.root.join("../bin/gates").read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
  end

  it "runs the env check" do
    expect(commands).to include(a_string_matching(%r{bin/check-env\b}))
  end

  it "runs the gitleaks secret scan over the full git history" do
    expect(commands).to include(a_string_matching(/\Agitleaks git\b/))
  end
end
