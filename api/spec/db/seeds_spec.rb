require "rails_helper"

# R32: one seed command (bin/rails db:seed, which runs db/seeds.rb) loads the slots, the demo users
# and the golden set, prints the demo credentials, and is safe to run again.
RSpec.describe "db/seeds.rb" do
  let(:auth) { FakeSupabaseAuthAdmin.new.install }
  let(:golden_count) { JSON.parse(Rails.root.join("eval/golden/labels.json").read).size }

  before { auth }

  # Runs the seed the way bin/rails db:seed does and returns what it printed.
  def run_seed
    output = StringIO.new
    original = $stdout
    $stdout = output
    Rails.application.load_seed
    output.string
  ensure
    $stdout = original
  end

  # The seeded rows and Auth users, failing rather than letting an empty seed pass vacuously.
  def seeded_slots
    expect(Slot.count).to be > 0
    Slot.order(:starts_at).to_a
  end

  def seeded_users
    expect(auth.users).not_to be_empty
    auth.users
  end

  it "starts from an empty test database" do
    expect(Slot.count).to eq(0)
    expect(Booking.count).to eq(0)
  end

  describe "slots" do
    it "loads open slots that are all in the future" do
      run_seed

      seeded_slots.each do |slot|
        expect(slot.starts_at).to be > Time.current
        expect(slot.ends_at).to be > slot.starts_at
      end
      expect(Slot.open.count).to eq(Slot.count)
    end

    it "stores the slots in UTC, even when seeded from a non-UTC time zone" do
      Time.use_zone("Pacific/Kiritimati") { run_seed }

      seeded_slots.each do |slot|
        expect(slot.starts_at.utc_offset).to eq(0)
        expect(slot.summary[:starts_at]).to match(SchedulingHelpers::ISO_8601_UTC)
        expect(slot.starts_at).to be > Time.current
      end
      expect(Slot.columns_hash["starts_at"].sql_type).to include("with time zone")
    end
  end

  describe "demo users" do
    it "creates the demo users as confirmed Supabase Auth users through the admin API" do
      run_seed

      seeded_users.each do |user|
        expect(user.email_confirm).to be(true)
        expect(user.password).to be_a(String).and(satisfy { |password| password.length >= 8 })
      end
    end

    it "uses only reserved, non-routable email domains" do
      run_seed

      seeded_users.each { |user| expect(user.email).to match(/@example\.(com|org|net)\z|\.test\z/) }
    end

    it "prints every demo user's email and password" do
      output = run_seed

      seeded_users.each do |user|
        expect(output).to include(user.email)
        expect(output).to include(user.password)
      end
    end

    it "uses known credentials that are the same on every run" do
      first = run_seed
      credentials = seeded_users.map { |user| [ user.email, user.password ] }

      fresh = FakeSupabaseAuthAdmin.new.install
      run_seed

      expect(fresh.users.map { |user| [ user.email, user.password ] }).to eq(credentials)
      credentials.each { |email, password| expect(first).to include(email, password) }
    end
  end

  describe "golden set" do
    it "registers the golden set and reports its labeled documents" do
      output = run_seed

      expect(output).to match(/golden set/i)
      expect(output).to include(golden_count.to_s)
    end

    it "fails when the golden set is missing, instead of seeding without it" do
      Dir.mktmpdir do |empty|
        ENV["GOLDEN_DIR"] = empty
        expect { run_seed }.to raise_error(StandardError, /golden set/i)
      ensure
        ENV.delete("GOLDEN_DIR")
      end
    end
  end

  describe "idempotency" do
    it "creates no duplicate slots or demo users when run twice" do
      run_seed
      slot_times = seeded_slots.map { |slot| [ slot.starts_at, slot.ends_at ] }
      users = seeded_users.map(&:email)

      expect { run_seed }.not_to raise_error

      expect(Slot.order(:starts_at).pluck(:starts_at, :ends_at)).to eq(slot_times)
      expect(Slot.group(:starts_at).having("count(*) > 1").count).to be_empty
      expect(auth.users.map(&:email)).to eq(users)
    end

    it "still prints the demo credentials on the second run" do
      run_seed
      output = run_seed

      seeded_users.each { |user| expect(output).to include(user.email, user.password) }
    end
  end
end
