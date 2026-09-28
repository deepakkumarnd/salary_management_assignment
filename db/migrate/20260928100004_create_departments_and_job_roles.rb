class CreateDepartmentsAndJobRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :departments do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, collation: "NOCASE"
      t.timestamps
      t.index [ :organization_id, :name ], unique: true
    end

    create_table :job_roles do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, collation: "NOCASE"
      t.timestamps
      t.index [ :organization_id, :name ], unique: true
    end
  end
end
