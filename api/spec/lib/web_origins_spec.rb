require "rails_helper"

RSpec.describe WebOrigins do
  describe ".from_env" do
    it "reads a comma-separated WEB_ORIGIN" do
      env = { "WEB_ORIGIN" => "https://app.example.test, https://staging.example.test" }

      expect(described_class.from_env(env, production: true))
        .to eq(%w[https://app.example.test https://staging.example.test])
    end

    it "defaults to the local web app outside production" do
      expect(described_class.from_env({}, production: false)).to eq([ "http://localhost:3000" ])
    end

    it "fails fast in production when WEB_ORIGIN is missing" do
      expect { described_class.from_env({}, production: true) }
        .to raise_error(WebOrigins::MissingError, /WEB_ORIGIN/)
    end

    it "fails fast in production when WEB_ORIGIN is blank" do
      expect { described_class.from_env({ "WEB_ORIGIN" => " , " }, production: true) }
        .to raise_error(WebOrigins::MissingError, /WEB_ORIGIN/)
    end
  end
end
