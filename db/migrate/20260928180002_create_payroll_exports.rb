class CreatePayrollExports < ActiveRecord::Migration[8.1]
  def change
    # A log of every downloaded payroll file; the file itself is never stored.
    create_table :payroll_exports do |t|
      t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :country,      null: false, foreign_key: { on_delete: :restrict }
      t.date    :period_start, null: false                           # first day of the pay month
      t.integer :row_count,    null: false
      t.string  :sha256,       null: false                           # checksum of the file as downloaded
      t.references :exported_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.datetime :created_at, null: false

      t.index [ :organization_id, :created_at ]
      t.index [ :organization_id, :country_id, :period_start, :created_at ], name: "index_payroll_exports_for_cutoff"
    end
  end
end
