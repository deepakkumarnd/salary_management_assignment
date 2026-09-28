class CreateSalaryRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_revisions do |t|
      t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :employee,     null: false, index: false, foreign_key: { on_delete: :restrict }
      t.date    :effective_on, null: false                           # applies from the start of this day
      t.integer :basic_pay,    null: false                           # annual, employee's local currency
      t.string  :reason,       null: false
      t.text    :notes
      t.references :created_by, null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.datetime :voided_at                                          # nil → in force
      t.references :voided_by, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :void_reason
      t.timestamps

      t.index [ :employee_id, :effective_on ], unique: true, where: "voided_at IS NULL",
              name: "index_salary_revisions_in_force_per_day"          # one per day; serves "basic as of"
      t.index [ :employee_id ], unique: true, where: "reason = 'hire' AND voided_at IS NULL",
              name: "one_hire_revision_per_employee"
      t.index [ :employee_id, :created_at ]                            # full history, including voided rows
      t.index [ :organization_id, :created_at ]                        # entered this month (backdated detection)

      t.check_constraint "basic_pay > 0", name: "salary_revisions_basic_positive"
      t.check_constraint "reason IN ('hire','appraisal','promotion','market_adjustment','correction')",
                         name: "salary_revisions_reason"
      t.check_constraint "(voided_at IS NULL) = (voided_by_id IS NULL) AND (voided_at IS NULL) = (void_reason IS NULL)",
                         name: "salary_revisions_void_fields_together"
    end
  end
end
