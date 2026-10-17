require "rails_helper"

# R32: following only the README gets the app running. The troubleshooting entry for a stale
# Supabase stack (another checkout's stack holding the same project id) must give a command that
# works even when that other checkout has been deleted, so it can't be a bare `supabase stop`
# run "in that checkout".
RSpec.describe "README.md" do
  let(:repo_root) { Rails.root.join("..").expand_path }
  let(:readme) { repo_root.join("README.md").read }
  let(:project_id) { repo_root.join("supabase/config.toml").read[/^project_id\s*=\s*"([^"]+)"/, 1] }
  let(:troubleshooting) { readme[/^## Troubleshooting\n(.*?)(?=^## )/m, 1].to_s }

  it "R32: the stale Supabase stack fix stops it by project id, so it works when the other checkout is gone" do
    expect(project_id).to be_present
    expect(troubleshooting).to include("supabase stop --project-id #{project_id}")
  end
end
