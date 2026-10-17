require "rails_helper"
require "open3"

# R32: bin/setup on a clean checkout. The external tools (Docker, Supabase CLI, npm, bundler,
# Tesseract, libvips) and bin/rails are stubbed on PATH, so this runs only the script's own logic
# against a copy of the .env.example files.
RSpec.describe "bin/setup" do
  let(:repo_root) { Rails.root.join("..").expand_path }

  let(:stubs) do
    {
      "npm" => "exit 0",
      "bundle" => "exit 0",
      "tesseract" => 'echo "List of available languages (1):"; echo eng',
      "vips" => 'echo "heifload"',
      "docker" => 'echo "DB_PORT=${DB_PORT:-} $*" >> "$STUB_LOG"; exit 0',
      "supabase" => <<~SH
        if [ "$1" = "status" ]; then
          echo 'API_URL="http://127.0.0.1:54321"'
          echo 'ANON_KEY="local-anon-key"'
          echo 'SERVICE_ROLE_KEY="local-service-role-key"'
        fi
        exit 0
      SH
    }
  end

  def run_setup(env = {})
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(%W[#{root}/bin #{root}/api/bin #{root}/web #{root}/supabase #{root}/stubs])
      FileUtils.cp(repo_root.join("bin/setup"), "#{root}/bin/setup")
      FileUtils.cp(repo_root.join("api/.env.example"), "#{root}/api/.env.example")
      FileUtils.cp(repo_root.join("web/.env.example"), "#{root}/web/.env.example")
      File.write("#{root}/supabase/signing_keys.json", "[{}]\n")
      File.write("#{root}/api/bin/rails", "#!/bin/sh\nexit 0\n")
      FileUtils.chmod(0o755, "#{root}/api/bin/rails")
      stubs.each do |name, body|
        File.write("#{root}/stubs/#{name}", "#!/bin/sh\n#{body}\n")
        FileUtils.chmod(0o755, "#{root}/stubs/#{name}")
      end
      log = "#{root}/stub.log"
      full_env = { "PATH" => "#{root}/stubs:#{ENV.fetch('PATH')}", "STUB_LOG" => log, "DB_PORT" => nil }.merge(env)

      output, status = Open3.capture2e(full_env, "#{root}/bin/setup", chdir: root)
      expect(status).to be_success, output

      yield File.read("#{root}/api/.env"), (File.exist?(log) ? File.read(log) : "")
    end
  end

  def env_value(dotenv, key)
    dotenv[/^#{key}=(.*)$/, 1]
  end

  it "R32: with DB_PORT set, writes that port into the api/.env it generates" do
    run_setup("DB_PORT" => "5499") do |api_env, _docker_calls|
      expect(env_value(api_env, "DB_PORT")).to eq("5499")
    end
  end

  it "R32: with DB_PORT set, starts Postgres on the same port the generated api/.env points the API at" do
    run_setup("DB_PORT" => "5499") do |api_env, docker_calls|
      compose_call = docker_calls.lines.find { |line| line.include?("compose") && line.include?("up") }

      expect(compose_call).to start_with("DB_PORT=5499 ")
      expect(env_value(api_env, "DB_PORT")).to eq("5499")
    end
  end

  it "R32: without DB_PORT, the generated api/.env keeps the default port 5433" do
    run_setup do |api_env, docker_calls|
      expect(env_value(api_env, "DB_PORT")).to eq("5433")
      expect(docker_calls.lines.find { |line| line.include?("compose") }).to start_with("DB_PORT=5433 ")
    end
  end
end
