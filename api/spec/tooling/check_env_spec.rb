require "rails_helper"
require "open3"

# R33: bin/check-env (at the repo root) compares every environment variable the code in api/ and
# web/ reads, NEXT_PUBLIC_* included, against api/.env.example and web/.env.example, and fails
# listing the ones that are missing or listed without an explanation.
#
# Usage: bin/check-env [ROOT]   (ROOT defaults to the repo root)
#
# A variable counts as explained when a comment line sits above it in the same block (no blank
# line between the comment and the variable). Test code (api/spec, *.test.*), node_modules and
# build output are not app code and aren't scanned.
RSpec.describe "bin/check-env" do
  let(:repo_root) { Rails.root.join("..").expand_path }
  let(:script) { repo_root.join("bin/check-env").to_s }

  let(:api_example) do
    <<~ENV
      # --- Services ---

      # Base URL of the widget service.
      WIDGET_URL=https://widget.example.test
      # Key for the widget service.
      WIDGET_KEY=replace-me

      # Local Postgres. Defaults match docker-compose.yml.
      DB_HOST=localhost
      DB_PORT=5433
    ENV
  end

  let(:web_example) do
    <<~ENV
      # Base URL of the API.
      NEXT_PUBLIC_API_URL=http://localhost:3001
      # Seconds before the banner hides.
      NEXT_PUBLIC_BANNER_SECONDS=10
    ENV
  end

  let(:files) do
    {
      "api/.env.example" => api_example,
      "web/.env.example" => web_example,
      "api/app/services/widget.rb" => <<~RUBY,
        class Widget
          URL = ENV.fetch("WIDGET_URL")
          KEY = ENV['WIDGET_KEY']
        end
      RUBY
      "api/config/database.yml" => <<~YAML,
        test:
          host: <%= ENV.fetch("DB_HOST") { "localhost" } %>
          port: <%= ENV["DB_PORT"] || 5433 %>
      YAML
      "web/src/api.ts" => "export const base = process.env.NEXT_PUBLIC_API_URL ?? ''\n",
      "web/src/banner.tsx" => "export const seconds = Number(process.env['NEXT_PUBLIC_BANNER_SECONDS'])\n",
      # Not app code: never scanned.
      "api/spec/widget_spec.rb" => "ENV[\"SPEC_ONLY_SETTING\"] = \"x\"\n",
      "web/src/api.test.ts" => "process.env.TEST_ONLY_SETTING = 'x'\n",
      "web/playwright.config.ts" => "const port = process.env.E2E_ONLY_SETTING\n",
      "web/e2e/support/stack.ts" => "process.env.E2E_HARNESS_SETTING\n",
      "web/node_modules/some-lib/index.js" => "module.exports = process.env.LIBRARY_SETTING\n",
      "web/.next/server/chunk.js" => "process.env.BUILD_OUTPUT_SETTING\n"
    }
  end

  def check(tree)
    Dir.mktmpdir do |root|
      tree.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), content)
      end
      output, status = Open3.capture2e(script, root)
      [ output, status ]
    end
  end

  it "passes a tree whose .env.example files list and explain every variable the code reads" do
    output, status = check(files)

    expect(status).to be_success, output
  end

  it "fails listing an API variable the code reads that .env.example doesn't list" do
    tree = files.merge("api/.env.example" => api_example.sub("# Key for the widget service.\nWIDGET_KEY=replace-me\n", ""))

    output, status = check(tree)

    expect(status).not_to be_success
    expect(output).to include("WIDGET_KEY")
    expect(output).not_to include("WIDGET_URL")
  end

  it "fails listing a NEXT_PUBLIC_ variable the web code reads that .env.example doesn't list" do
    tree = files.merge("web/.env.example" => "# Base URL of the API.\nNEXT_PUBLIC_API_URL=http://localhost:3001\n")

    output, status = check(tree)

    expect(status).not_to be_success
    expect(output).to include("NEXT_PUBLIC_BANNER_SECONDS")
    expect(output).not_to include("NEXT_PUBLIC_API_URL")
  end

  it "fails listing a variable read in ERB config that .env.example doesn't list" do
    tree = files.merge("api/config/database.yml" => "test:\n  user: <%= ENV.fetch(\"DB_USER\") { \"postgres\" } %>\n")

    output, status = check(tree)

    expect(status).not_to be_success
    expect(output).to include("DB_USER")
  end

  it "fails listing a variable that .env.example lists without explaining it" do
    tree = files.merge("api/.env.example" => api_example.sub("# Key for the widget service.\n", "\n"))

    output, status = check(tree)

    expect(status).not_to be_success
    expect(output).to include("WIDGET_KEY")
    expect(output).not_to include("WIDGET_URL")
  end

  it "doesn't count a web variable as documented by the API's .env.example" do
    tree = files.merge(
      "api/.env.example" => "#{api_example}# Seconds before the banner hides.\nNEXT_PUBLIC_BANNER_SECONDS=10\n",
      "web/.env.example" => "# Base URL of the API.\nNEXT_PUBLIC_API_URL=http://localhost:3001\n"
    )

    output, status = check(tree)

    expect(status).not_to be_success
    expect(output).to include("NEXT_PUBLIC_BANNER_SECONDS")
  end

  it "ignores variables read only by tests, dependencies and build output" do
    output, status = check(files)

    expect(status).to be_success, output
    %w[SPEC_ONLY_SETTING TEST_ONLY_SETTING E2E_ONLY_SETTING E2E_HARNESS_SETTING LIBRARY_SETTING
       BUILD_OUTPUT_SETTING].each do |name|
      expect(output).not_to include(name)
    end
  end

  it "passes on this repository" do
    output, status = Open3.capture2e(script, chdir: repo_root.to_s)

    expect(status).to be_success, output
  end
end
