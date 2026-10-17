require "rails_helper"

# R17: images from uploads that were never confirmed are deleted after 1 hour. The purge runs on
# its schedule in development too, so a local demo doesn't keep abandoned images.
RSpec.describe "config/recurring.yml" do
  let(:recurring) do
    YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
  end

  %w[development production].each do |environment|
    it "R17: schedules the upload purge job in #{environment}" do
      task = recurring.fetch(environment, nil).to_h.values.find { |t| t["class"] == "Documents::PurgeExpiredUploadsJob" }

      expect(task).to be_present, "no Documents::PurgeExpiredUploadsJob task for #{environment}"
      expect(task["schedule"]).to be_present
    end
  end

  it "R17: the development schedule is a valid recurring schedule that runs at least hourly" do
    task = recurring.fetch("development", nil).to_h.values.find { |t| t["class"] == "Documents::PurgeExpiredUploadsJob" }
    expect(task).to be_present

    schedule = Fugit.parse(task["schedule"])
    expect(schedule).to be_a(Fugit::Cron)
    now = Time.current
    expect(schedule.next_time(now).to_t - now).to be <= 1.hour
  end
end
