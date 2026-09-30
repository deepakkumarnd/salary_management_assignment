class CreateEmployeeImports < ActiveRecord::Migration[8.1]
  def change
    # One uploaded employee CSV (the file itself is an Active Storage attachment) and how far its background job got.
    create_table :employee_imports do |t|
      t.references :organization, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :uploaded_by,  null: false, foreign_key: { to_table: :users, on_delete: :restrict }
      t.string  :status,         null: false, default: "queued"
      t.integer :total_rows                                          # counted when the job starts
      t.integer :processed_rows, null: false, default: 0             # the job resumes after this many rows
      t.integer :created_count,  null: false, default: 0
      t.integer :skipped_count,  null: false, default: 0
      t.json    :new_departments,        null: false, default: []    # names created by this import
      t.json    :new_job_roles,          null: false, default: []
      t.json    :missing_pay_structures, null: false, default: []    # [{country_id, country, job_role_id, job_role, rows}]
      t.string  :error_message                                       # why a failed import stopped
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps

      t.index [ :organization_id, :created_at ]
      t.check_constraint "status IN ('queued','processing','completed','failed')", name: "employee_imports_status"
    end

    # A row that wasn't imported: where it was in the file, what it said, and every reason it was skipped.
    create_table :employee_import_skipped_rows do |t|
      t.references :employee_import, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :row_number, null: false                             # as in a spreadsheet: the header is row 1
      t.string  :email
      t.json    :data,       null: false, default: {}                # the row's known columns, as uploaded
      t.json    :reasons,    null: false, default: []

      t.index [ :employee_import_id, :row_number ], unique: true
    end
  end
end
