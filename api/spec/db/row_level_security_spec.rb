require "rails_helper"

# R19: row-level security is enabled on every table, with no policies for client roles, so a
# leaked anon key reads nothing. The catalog is queried rather than a list of names, so any
# table added later fails this spec until it has RLS too.
RSpec.describe "Row-level security" do
  let(:connection) { ActiveRecord::Base.connection }

  let(:public_tables) do
    connection.select_values(<<~SQL)
      SELECT c.relname FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
      ORDER BY c.relname
    SQL
  end

  it "finds the app's tables (guards against an empty catalog query)" do
    expect(public_tables).to include("audit_events")
  end

  it "R19: is enabled on every table in the public schema" do
    without_rls = connection.select_values(<<~SQL)
      SELECT c.relname FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
      ORDER BY c.relname
    SQL

    expect(without_rls).to be_empty, "tables without row-level security: #{without_rls.join(', ')}"
  end

  it "R19: grants no policy to the anon, authenticated or public roles" do
    client_policies = connection.select_rows(<<~SQL)
      SELECT tablename, policyname FROM pg_policies
      WHERE schemaname = 'public' AND roles && ARRAY['anon', 'authenticated', 'public']::name[]
    SQL

    expect(client_policies).to be_empty
  end
end
