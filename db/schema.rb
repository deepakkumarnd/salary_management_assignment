# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_30_100001) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "countries", force: :cascade do |t|
    t.string "name", null: false
    t.string "currency_code", limit: 3, null: false
    t.index ["name"], name: "index_countries_on_name", unique: true
    t.check_constraint "length(currency_code) = 3", name: "countries_currency_code_length"
  end

  create_table "country_allowances", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "country_id", null: false
    t.string "name", null: false, collation: "NOCASE"
    t.integer "percent_bp", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_country_allowances_on_country_id"
    t.index ["organization_id", "country_id", "name"], name: "idx_on_organization_id_country_id_name_aceed5af40", unique: true
    t.index ["organization_id"], name: "index_country_allowances_on_organization_id"
    t.index ["updated_by_id"], name: "index_country_allowances_on_updated_by_id"
    t.check_constraint "percent_bp BETWEEN 1 AND 20000", name: "country_allowances_percent_range"
  end

  create_table "departments", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "name", null: false, collation: "NOCASE"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_departments_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_departments_on_organization_id"
  end

  create_table "employee_import_skipped_rows", force: :cascade do |t|
    t.integer "employee_import_id", null: false
    t.integer "row_number", null: false
    t.string "email"
    t.json "data", default: {}, null: false
    t.json "reasons", default: [], null: false
    t.index ["employee_import_id", "row_number"], name: "idx_on_employee_import_id_row_number_cedfd1a704", unique: true
  end

  create_table "employee_imports", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "uploaded_by_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "total_rows"
    t.integer "processed_rows", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.json "new_departments", default: [], null: false
    t.json "new_job_roles", default: [], null: false
    t.json "missing_pay_structures", default: [], null: false
    t.string "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "created_at"], name: "index_employee_imports_on_organization_id_and_created_at"
    t.index ["uploaded_by_id"], name: "index_employee_imports_on_uploaded_by_id"
    t.check_constraint "status IN ('queued','processing','completed','failed')", name: "employee_imports_status"
  end

  create_table "employees", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "employee_code", null: false
    t.string "full_name", null: false
    t.string "email", null: false
    t.integer "country_id", null: false
    t.integer "job_role_id", null: false
    t.integer "department_id", null: false
    t.string "employment_type", null: false
    t.date "hire_date", null: false
    t.date "employment_end_date"
    t.string "exit_reason"
    t.text "exit_notes"
    t.integer "lock_version", default: 0, null: false
    t.integer "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id", "job_role_id"], name: "index_employees_on_country_id_and_job_role_id"
    t.index ["department_id"], name: "index_employees_on_department_id"
    t.index ["job_role_id"], name: "index_employees_on_job_role_id"
    t.index ["organization_id", "country_id", "department_id"], name: "idx_on_organization_id_country_id_department_id_db84a8b901"
    t.index ["organization_id", "department_id"], name: "index_employees_on_organization_id_and_department_id"
    t.index ["organization_id", "email"], name: "index_employees_on_org_and_email_without_exit", unique: true, where: "employment_end_date IS NULL"
    t.index ["organization_id", "employee_code"], name: "index_employees_on_organization_id_and_employee_code", unique: true
    t.index ["organization_id", "employment_end_date"], name: "index_employees_on_organization_id_and_employment_end_date"
    t.index ["organization_id", "full_name"], name: "index_employees_on_organization_id_and_full_name"
    t.index ["organization_id", "job_role_id"], name: "index_employees_on_organization_id_and_job_role_id"
    t.index ["updated_by_id"], name: "index_employees_on_updated_by_id"
    t.check_constraint "(employment_end_date IS NULL) = (exit_reason IS NULL)", name: "employees_exit_fields_together"
    t.check_constraint "employment_end_date IS NULL OR employment_end_date >= hire_date", name: "employees_end_after_hire"
    t.check_constraint "employment_type IN ('full_time','part_time','contractor')", name: "employees_employment_type"
    t.check_constraint "exit_reason IS NULL OR exit_reason IN ('resignation','termination','retirement','end_of_contract','internal_transfer','recorded_in_error','other')", name: "employees_exit_reason"
  end

  create_table "job_roles", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "name", null: false, collation: "NOCASE"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_job_roles_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_job_roles_on_organization_id"
  end

  create_table "organization_countries", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "country_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_organization_countries_on_country_id"
    t.index ["organization_id", "country_id"], name: "index_organization_countries_on_organization_id_and_country_id", unique: true
    t.index ["organization_id"], name: "index_organization_countries_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "employee_code_prefix", null: false
    t.integer "next_employee_number", default: 1, null: false
    t.integer "standard_hours_per_week", default: 40, null: false
    t.datetime "setup_completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "pay_data_version", default: 0, null: false
    t.check_constraint "employee_code_prefix NOT GLOB '*[^A-Z]*' AND length(employee_code_prefix) BETWEEN 2 AND 6", name: "organizations_prefix_format"
    t.check_constraint "standard_hours_per_week BETWEEN 1 AND 80", name: "organizations_hours_range"
  end

  create_table "pay_structure_allowances", force: :cascade do |t|
    t.integer "pay_structure_id", null: false
    t.string "name", null: false, collation: "NOCASE"
    t.integer "percent_bp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pay_structure_id", "name"], name: "index_pay_structure_allowances_on_pay_structure_id_and_name", unique: true
    t.index ["pay_structure_id"], name: "index_pay_structure_allowances_on_pay_structure_id"
    t.check_constraint "percent_bp BETWEEN 1 AND 20000", name: "pay_structure_allowances_percent_range"
  end

  create_table "pay_structures", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "country_id", null: false
    t.integer "job_role_id", null: false
    t.integer "default_basic_pay", null: false
    t.integer "variable_pay_percent_bp", default: 0, null: false
    t.integer "overtime_percent_bp", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id", "job_role_id"], name: "index_pay_structures_on_country_id_and_job_role_id", unique: true
    t.index ["job_role_id"], name: "index_pay_structures_on_job_role_id"
    t.index ["organization_id"], name: "index_pay_structures_on_organization_id"
    t.index ["updated_by_id"], name: "index_pay_structures_on_updated_by_id"
    t.check_constraint "default_basic_pay > 0", name: "pay_structures_basic_positive"
    t.check_constraint "overtime_percent_bp BETWEEN 0 AND 40000", name: "pay_structures_overtime_range"
    t.check_constraint "variable_pay_percent_bp BETWEEN 0 AND 20000", name: "pay_structures_variable_range"
  end

  create_table "payroll_deductions", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "employee_id", null: false
    t.date "period_start", null: false
    t.string "kind", null: false
    t.integer "unpaid_half_days"
    t.integer "amount"
    t.string "description"
    t.integer "lock_version", default: 0, null: false
    t.integer "created_by_id", null: false
    t.integer "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_payroll_deductions_on_created_by_id"
    t.index ["employee_id", "period_start"], name: "one_unpaid_leave_per_employee_month", unique: true, where: "kind = 'unpaid_leave'"
    t.index ["employee_id"], name: "index_payroll_deductions_on_employee_id"
    t.index ["organization_id", "period_start"], name: "index_payroll_deductions_on_organization_id_and_period_start"
    t.index ["updated_by_id"], name: "index_payroll_deductions_on_updated_by_id"
    t.check_constraint "(kind = 'unpaid_leave' AND unpaid_half_days > 0 AND amount IS NULL AND description IS NULL) OR (kind = 'other' AND amount > 0 AND description IS NOT NULL AND unpaid_half_days IS NULL)", name: "payroll_deductions_kind_fields"
    t.check_constraint "kind IN ('unpaid_leave','other')", name: "payroll_deductions_kind"
    t.check_constraint "period_start = date(period_start, 'start of month')", name: "payroll_deductions_month_start"
  end

  create_table "payroll_exports", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "country_id", null: false
    t.date "period_start", null: false
    t.integer "row_count", null: false
    t.string "sha256", null: false
    t.integer "exported_by_id", null: false
    t.datetime "created_at", null: false
    t.index ["country_id"], name: "index_payroll_exports_on_country_id"
    t.index ["exported_by_id"], name: "index_payroll_exports_on_exported_by_id"
    t.index ["organization_id", "country_id", "period_start", "created_at"], name: "index_payroll_exports_for_cutoff"
    t.index ["organization_id", "created_at"], name: "index_payroll_exports_on_organization_id_and_created_at"
  end

  create_table "salary_revisions", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "employee_id", null: false
    t.date "effective_on", null: false
    t.integer "basic_pay", null: false
    t.string "reason", null: false
    t.text "notes"
    t.integer "created_by_id", null: false
    t.datetime "voided_at"
    t.integer "voided_by_id"
    t.string "void_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_salary_revisions_on_created_by_id"
    t.index ["employee_id", "created_at"], name: "index_salary_revisions_on_employee_id_and_created_at"
    t.index ["employee_id", "effective_on"], name: "index_salary_revisions_in_force_per_day", unique: true, where: "voided_at IS NULL"
    t.index ["employee_id"], name: "one_hire_revision_per_employee", unique: true, where: "reason = 'hire' AND voided_at IS NULL"
    t.index ["organization_id", "created_at"], name: "index_salary_revisions_on_organization_id_and_created_at"
    t.index ["voided_by_id"], name: "index_salary_revisions_on_voided_by_id"
    t.check_constraint "(voided_at IS NULL) = (voided_by_id IS NULL) AND (voided_at IS NULL) = (void_reason IS NULL)", name: "salary_revisions_void_fields_together"
    t.check_constraint "basic_pay > 0", name: "salary_revisions_basic_positive"
    t.check_constraint "reason IN ('hire','appraisal','promotion','market_adjustment','correction')", name: "salary_revisions_reason"
  end

  create_table "users", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "full_name", null: false
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "deactivated_at"
    t.integer "deactivated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deactivated_by_id"], name: "index_users_on_deactivated_by_id"
    t.index ["email"], name: "index_users_on_email", unique: true, where: "deactivated_at IS NULL"
    t.index ["organization_id"], name: "index_users_on_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "country_allowances", "countries", on_delete: :restrict
  add_foreign_key "country_allowances", "organizations", on_delete: :cascade
  add_foreign_key "country_allowances", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "departments", "organizations", on_delete: :cascade
  add_foreign_key "employee_import_skipped_rows", "employee_imports", on_delete: :cascade
  add_foreign_key "employee_imports", "organizations", on_delete: :cascade
  add_foreign_key "employee_imports", "users", column: "uploaded_by_id", on_delete: :restrict
  add_foreign_key "employees", "countries", on_delete: :restrict
  add_foreign_key "employees", "departments", on_delete: :restrict
  add_foreign_key "employees", "organizations", on_delete: :cascade
  add_foreign_key "employees", "pay_structures", column: ["country_id", "job_role_id"], primary_key: ["country_id", "job_role_id"], on_delete: :restrict
  add_foreign_key "employees", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "job_roles", "organizations", on_delete: :cascade
  add_foreign_key "organization_countries", "countries", on_delete: :restrict
  add_foreign_key "organization_countries", "organizations", on_delete: :cascade
  add_foreign_key "pay_structure_allowances", "pay_structures", on_delete: :cascade
  add_foreign_key "pay_structures", "countries", on_delete: :restrict
  add_foreign_key "pay_structures", "job_roles", on_delete: :restrict
  add_foreign_key "pay_structures", "organizations", on_delete: :cascade
  add_foreign_key "pay_structures", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "payroll_deductions", "employees", on_delete: :restrict
  add_foreign_key "payroll_deductions", "organizations", on_delete: :cascade
  add_foreign_key "payroll_deductions", "users", column: "created_by_id", on_delete: :restrict
  add_foreign_key "payroll_deductions", "users", column: "updated_by_id", on_delete: :restrict
  add_foreign_key "payroll_exports", "countries", on_delete: :restrict
  add_foreign_key "payroll_exports", "organizations", on_delete: :cascade
  add_foreign_key "payroll_exports", "users", column: "exported_by_id", on_delete: :restrict
  add_foreign_key "salary_revisions", "employees", on_delete: :restrict
  add_foreign_key "salary_revisions", "organizations", on_delete: :cascade
  add_foreign_key "salary_revisions", "users", column: "created_by_id", on_delete: :restrict
  add_foreign_key "salary_revisions", "users", column: "voided_by_id", on_delete: :restrict
  add_foreign_key "users", "organizations", on_delete: :restrict
  add_foreign_key "users", "users", column: "deactivated_by_id", on_delete: :restrict
end
