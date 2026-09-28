class CreatePayrollDeductions < ActiveRecord::Migration[8.1]
  def change
    create_table :payroll_deductions do |t|
      t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :employee,     null: false, foreign_key: { on_delete: :restrict }
      t.date    :period_start,     null: false                       # first day of the pay month
      t.string  :kind,             null: false                       # 'unpaid_leave' | 'other'
      t.integer :unpaid_half_days                                    # unpaid_leave only: 3 = 1.5 days
      t.integer :amount                                              # other only: whole units, local currency
      t.string  :description                                         # other only
      t.integer :lock_version,     null: false, default: 0
      t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :restrict }
      t.timestamps

      t.index [ :organization_id, :period_start ]                    # month page + export
      t.index [ :employee_id, :period_start ], unique: true, where: "kind = 'unpaid_leave'",
              name: "one_unpaid_leave_per_employee_month"
      t.check_constraint "period_start = date(period_start, 'start of month')", name: "payroll_deductions_month_start"
      t.check_constraint "kind IN ('unpaid_leave','other')", name: "payroll_deductions_kind"
      t.check_constraint "(kind = 'unpaid_leave' AND unpaid_half_days > 0 AND amount IS NULL AND description IS NULL)" \
                         " OR (kind = 'other' AND amount > 0 AND description IS NOT NULL AND unpaid_half_days IS NULL)",
                         name: "payroll_deductions_kind_fields"
    end
  end
end
