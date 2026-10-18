require "rails_helper"

# Deploy readiness: the two Railway services (api/ and web/ roots) build from their Dockerfiles.
# The real proof is a local docker build and boot (docs/deploy.md); these guard the settings.
RSpec.describe "Railway service config" do
  let(:repo) { Rails.root.join("..") }

  def toml(path)
    repo.join(path).read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
  end

  describe "api/railway.toml" do
    let(:settings) { toml("api/railway.toml") }

    it "builds with the Dockerfile" do
      expect(settings).to include('builder = "DOCKERFILE"', 'dockerfilePath = "Dockerfile"')
    end

    it "health-checks /health" do
      expect(settings).to include('healthcheckPath = "/health"')
    end

    it "restarts on failure" do
      expect(settings).to include('restartPolicyType = "ON_FAILURE"')
    end

    it "keeps the image's command, so the entrypoint prepares the database and bucket" do
      expect(settings.grep(/\AstartCommand/)).to be_empty
    end
  end

  describe "api/Dockerfile" do
    let(:dockerfile) { repo.join("api/Dockerfile").read }

    it "installs libheif, so libvips can read HEIC photos" do
      expect(dockerfile).to match(/\blibheif1\b/)
    end
  end

  describe "web" do
    let(:settings) { toml("web/railway.toml") }
    let(:dockerfile) { repo.join("web/Dockerfile").read }
    let(:public_variables) { repo.join("web/.env.example").read.scan(/^(NEXT_PUBLIC_[A-Z0-9_]+)=/).flatten }

    it "builds with the Dockerfile" do
      expect(settings).to include('builder = "DOCKERFILE"', 'dockerfilePath = "Dockerfile"')
    end

    it "takes every NEXT_PUBLIC_ variable as a build argument, so next build inlines it" do
      expect(public_variables).not_to be_empty
      public_variables.each do |name|
        expect(dockerfile).to match(/^ARG #{name}$/).and match(/\b#{name}=\$#{name}\b/)
      end
    end

    it "builds before it starts, and starts on Railway's PORT on every interface" do
      expect(dockerfile).to match(/RUN npm run build/)
      expect(dockerfile).to match(/next start .*-H 0\.0\.0\.0.*-p \$\{?PORT/)
    end
  end
end
