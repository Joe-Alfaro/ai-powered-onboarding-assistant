require "rails_helper"

RSpec.describe RowLevelSecurity do
  let(:connection) { ActiveRecord::Base.connection }

  def rls_enabled?(table)
    connection.select_value("SELECT relrowsecurity FROM pg_class WHERE oid = '#{table}'::regclass")
  end

  it "enables RLS on a public table created without it" do
    connection.create_table(:spec_rls_tables)

    described_class.enable_on_public_tables(connection)

    expect(rls_enabled?("spec_rls_tables")).to be(true)
  end

  it "enables RLS on tables a migration run creates" do
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      def change = create_table(:spec_migrated_tables)
    end
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:migration_connection).and_return(connection)
    migrator = ActiveRecord::Migrator.new(:up, [ migration.new("SpecMigration", 1) ],
      connection.pool.schema_migration, connection.pool.internal_metadata, 1)

    ActiveRecord::Migration.suppress_messages { migrator.run }

    expect(rls_enabled?("spec_migrated_tables")).to be(true)
  end
end
