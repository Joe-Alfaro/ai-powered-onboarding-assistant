require Rails.root.join("lib/boot/row_level_security").to_s

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Schema::Definition.prepend(RowLevelSecurity::AfterSchemaLoad)
  ActiveRecord::Migrator.prepend(RowLevelSecurity::AfterMigrate)
end
