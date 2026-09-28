class CreateCountryAllowances < ActiveRecord::Migration[8.1]
  def change
    create_table :country_allowances do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :country,      null: false, foreign_key: { on_delete: :restrict }
      t.string  :name,         null: false, collation: "NOCASE"
      t.integer :percent_bp,   null: false                         # basis points: 4000 = 40.00%
      t.integer :lock_version, null: false, default: 0             # optimistic locking
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index [ :organization_id, :country_id, :name ], unique: true
      t.check_constraint "percent_bp BETWEEN 1 AND 20000", name: "country_allowances_percent_range"
    end
  end
end
