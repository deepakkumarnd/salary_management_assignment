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

ActiveRecord::Schema[8.1].define(version: 2026_09_28_100005) do
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
    t.check_constraint "employee_code_prefix NOT GLOB '*[^A-Z]*' AND length(employee_code_prefix) BETWEEN 2 AND 6", name: "organizations_prefix_format"
    t.check_constraint "standard_hours_per_week BETWEEN 1 AND 80", name: "organizations_hours_range"
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

  add_foreign_key "country_allowances", "countries", on_delete: :restrict
  add_foreign_key "country_allowances", "organizations", on_delete: :cascade
  add_foreign_key "country_allowances", "users", column: "updated_by_id", on_delete: :nullify
  add_foreign_key "departments", "organizations", on_delete: :cascade
  add_foreign_key "job_roles", "organizations", on_delete: :cascade
  add_foreign_key "organization_countries", "countries", on_delete: :restrict
  add_foreign_key "organization_countries", "organizations", on_delete: :cascade
  add_foreign_key "users", "organizations", on_delete: :restrict
  add_foreign_key "users", "users", column: "deactivated_by_id", on_delete: :restrict
end
