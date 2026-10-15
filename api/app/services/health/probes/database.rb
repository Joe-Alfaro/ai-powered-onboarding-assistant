module Health
  module Probes
    # Runs SELECT 1 on the given connection class's database.
    class Database
      def initialize(connection_class = ActiveRecord::Base)
        @connection_class = connection_class
      end

      def call
        @connection_class.connection_pool.with_connection { |connection| connection.select_value("SELECT 1") == 1 }
      end
    end
  end
end
