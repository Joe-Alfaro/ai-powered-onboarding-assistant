require "rails_helper"

# R20: Llm::PayloadBuilder is the only way out to an LLM, and no code path sends image bytes to
# one. These scan the source, so a new code path that breaks the rule fails here.
RSpec.describe "R20 the LLM has a single exit and never receives images" do
  let(:llm_dir) { Rails.root.join("app/services/llm") }
  let(:llm_endpoints) do
    %r{api\.anthropic\.com|api\.groq\.com|generativelanguage\.googleapis\.com|/chat/completions|/v1/messages}
  end
  let(:image_content) { /image_url|input_image|inline_data|media_type|base64|type["']?\s*(?:=>|:)\s*["']image["']/ }

  def source_files
    Rails.root.glob("{app,lib}/**/*.{rb,rake}")
  end

  def llm_files
    llm_dir.glob("**/*.rb")
  end

  def offenders(files, pattern)
    files.select { |file| File.read(file).match?(pattern) }.map { |file| file.relative_path_from(Rails.root).to_s }
  end

  it "has the LLM client code under app/services/llm" do
    expect(llm_files.map { |file| file.relative_path_from(llm_dir).to_s })
      .to include("client.rb", "payload_builder.rb", "adapters/anthropic.rb", "adapters/open_ai_compatible.rb")
  end

  it "mentions LLM provider endpoints only inside app/services/llm" do
    expect(offenders(source_files - llm_files, llm_endpoints)).to be_empty
  end

  it "uses the provider adapters only inside app/services/llm" do
    expect(offenders(source_files - llm_files, /Llm::Adapters|Adapters::(?:Anthropic|OpenAiCompatible)/)).to be_empty
  end

  it "creates Llm::Payload objects only in the payload builder" do
    others = llm_files.reject { |file| file.basename.to_s.in?(%w[payload_builder.rb payload.rb]) }

    expect(offenders(others + (source_files - llm_files), /Payload\.(?:new|send|allocate)|Payload\[/)).to be_empty
  end

  it "never builds image content for an LLM request" do
    expect(offenders(llm_files, image_content)).to be_empty
  end
end
