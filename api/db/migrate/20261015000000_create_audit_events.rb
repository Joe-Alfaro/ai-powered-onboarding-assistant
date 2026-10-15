class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.string :actor_ref, null: false
      t.string :action, null: false
      t.datetime :created_at, null: false
    end
    add_index :audit_events, :actor_ref
  end
end
