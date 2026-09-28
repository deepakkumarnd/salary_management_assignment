class CreatePayStructures < ActiveRecord::Migration[8.1]
  def change
    create_table :pay_structures do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :country,      null: false, index: false, foreign_key: { on_delete: :restrict }
      t.references :job_role,     null: false, foreign_key: { on_delete: :restrict }
      t.integer :default_basic_pay,       null: false                # annual, local currency, whole units
      t.integer :variable_pay_percent_bp, null: false, default: 0    # target variable, % of gross: 1000 = 10%
      t.integer :overtime_percent_bp,     null: false                # % of hourly basic: 15000 = 150%
      t.integer :lock_version,            null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index [ :country_id, :job_role_id ], unique: true            # job roles are per organization, so this is too
      t.check_constraint "default_basic_pay > 0", name: "pay_structures_basic_positive"
      t.check_constraint "variable_pay_percent_bp BETWEEN 0 AND 20000", name: "pay_structures_variable_range"
      t.check_constraint "overtime_percent_bp BETWEEN 0 AND 40000", name: "pay_structures_overtime_range"
    end

    create_table :pay_structure_allowances do |t|
      t.references :pay_structure, null: false, foreign_key: { on_delete: :cascade }
      t.string  :name,       null: false, collation: "NOCASE"
      t.integer :percent_bp, null: false
      t.timestamps
      t.index [ :pay_structure_id, :name ], unique: true
      t.check_constraint "percent_bp BETWEEN 1 AND 20000", name: "pay_structure_allowances_percent_range"
    end
  end
end
