# A real Active Record connection class pointed at a port nothing listens on, so specs see the
# genuine errors a downed Postgres produces instead of stubbed ones.
class UnreachableDatabase < ActiveRecord::Base
  self.abstract_class = true

  CONFIG = ActiveRecord::DatabaseConfigurations::HashConfig.new(
    "test", "unreachable",
    { adapter: "postgresql", host: "127.0.0.1", port: 1, database: "unreachable", connect_timeout: 1 }
  )
end

module UnreachableDatabaseHelper
  # Transactional fixtures would otherwise try to open a transaction on this pool, and fail.
  def self.included(group)
    return unless group.respond_to?(:database_transactions_config=)

    group.database_transactions_config = group.database_transactions_config.merge(unreachable: false)
  end

  def unreachable_database
    UnreachableDatabase.establish_connection(UnreachableDatabase::CONFIG)
    UnreachableDatabase
  end
end

RSpec.configure do |config|
  config.include UnreachableDatabaseHelper
  config.after { UnreachableDatabase.remove_connection }
end
