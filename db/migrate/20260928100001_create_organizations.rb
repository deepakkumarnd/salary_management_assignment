class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string   :name,                    null: false
      t.string   :employee_code_prefix,    null: false                # e.g. "ACME" → ACME-00042
      t.integer  :next_employee_number,    null: false, default: 1    # per-org sequence for employee IDs
      t.integer  :standard_hours_per_week, null: false, default: 40   # overtime hourly rate
      t.datetime :setup_completed_at                                 # nil → setup wizard is shown
      t.timestamps
      t.check_constraint "standard_hours_per_week BETWEEN 1 AND 80", name: "organizations_hours_range"
      t.check_constraint "employee_code_prefix NOT GLOB '*[^A-Z]*' AND length(employee_code_prefix) BETWEEN 2 AND 6",
                         name: "organizations_prefix_format"
    end
  end
end
