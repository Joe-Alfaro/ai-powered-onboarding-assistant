# Keeps row-level security enabled on every table in the public schema (R19), Rails' own
# schema_migrations and ar_internal_metadata included. With RLS on and no policies, Supabase's
# anon and authenticated roles read nothing, even with a leaked anon key. The API connects as
# the tables' owner, which RLS doesn't restrict.
#
# schema.rb can't record RLS, so instead of each migration remembering it, RLS is enabled after
# every migration run and every schema load. Tables added later get it without extra code.
module RowLevelSecurity
  module_function

  def enable_on_public_tables(connection)
    return unless connection.adapter_name == "PostgreSQL"

    tables = connection.select_values(<<~SQL)
      SELECT c.relname FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
    SQL
    tables.each { |table| connection.execute("ALTER TABLE #{connection.quote_table_name(table)} ENABLE ROW LEVEL SECURITY") }
  end

  # Prepended to ActiveRecord::Schema::Definition (schema.rb loads).
  module AfterSchemaLoad
    def define(...)
      result = super
      connection_pool.with_connection { |connection| RowLevelSecurity.enable_on_public_tables(connection) }
      result
    end
  end

  # Prepended to ActiveRecord::Migrator (db:migrate, db:prepare, and single-version runs).
  module AfterMigrate
    def migrate(...)
      result = super
      RowLevelSecurity.enable_on_public_tables(connection)
      result
    end

    def run(...)
      result = super
      RowLevelSecurity.enable_on_public_tables(connection)
      result
    end
  end
end
