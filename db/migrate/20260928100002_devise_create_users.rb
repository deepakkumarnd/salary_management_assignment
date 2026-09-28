class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :restrict }
      t.string   :full_name,          null: false
      t.string   :email,              null: false                     # unique among active accounts (index below)
      t.string   :encrypted_password, null: false

      # Recoverable
      t.string   :reset_password_token, index: { unique: true }
      t.datetime :reset_password_sent_at

      # Lockable
      t.integer  :failed_attempts, null: false, default: 0
      t.string   :unlock_token, index: { unique: true }
      t.datetime :locked_at

      # "Removed" by a colleague: can't sign in, email is free again
      t.datetime :deactivated_at
      t.references :deactivated_by, foreign_key: { to_table: :users, on_delete: :restrict }

      t.timestamps
      t.index :email, unique: true, where: "deactivated_at IS NULL"
    end
  end
end
