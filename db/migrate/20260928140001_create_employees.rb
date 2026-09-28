class CreateEmployees < ActiveRecord::Migration[8.1]
  EXIT_REASONS = %w[resignation termination retirement end_of_contract internal_transfer recorded_in_error other].freeze

  def change
    create_table :employees do |t|
      t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string  :employee_code,   null: false                        # readable ID, e.g. ACME-00042; immutable
      t.string  :full_name,       null: false
      t.string  :email,           null: false                        # normalised to lower case
      t.integer :country_id,      null: false                        # immutable after create
      t.integer :job_role_id,     null: false, index: true
      t.references :department,   null: false, foreign_key: { on_delete: :restrict }
      t.string  :employment_type, null: false
      t.date    :hire_date,       null: false
      t.date    :employment_end_date                                 # last working day; nil → no exit recorded
      t.string  :exit_reason
      t.text    :exit_notes
      t.integer :lock_version,    null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps

      t.index [ :organization_id, :employee_code ], unique: true
      t.index [ :organization_id, :email ], unique: true, where: "employment_end_date IS NULL",
              name: "index_employees_on_org_and_email_without_exit"
      t.index [ :organization_id, :country_id, :department_id ]
      t.index [ :organization_id, :department_id ]
      t.index [ :organization_id, :job_role_id ]
      t.index [ :organization_id, :full_name ]
      t.index [ :organization_id, :employment_end_date ]
      t.index [ :country_id, :job_role_id ]

      t.check_constraint "employment_type IN ('full_time','part_time','contractor')", name: "employees_employment_type"
      t.check_constraint "(employment_end_date IS NULL) = (exit_reason IS NULL)", name: "employees_exit_fields_together"
      t.check_constraint "employment_end_date IS NULL OR employment_end_date >= hire_date", name: "employees_end_after_hire"
      t.check_constraint "exit_reason IS NULL OR exit_reason IN (#{EXIT_REASONS.map { "'#{it}'" }.join(',')})",
                         name: "employees_exit_reason"

      t.foreign_key :countries, on_delete: :restrict
      # Every employee has a pay structure for their country + role (the pair is unique in pay_structures).
      t.foreign_key :pay_structures, column: %i[country_id job_role_id], primary_key: %i[country_id job_role_id],
                                     on_delete: :restrict
    end
  end
end
