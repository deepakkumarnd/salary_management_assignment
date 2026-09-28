class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|                                 # global reference data, no organization_id
      t.string :name,          null: false, index: { unique: true }
      t.string :currency_code, null: false, limit: 3               # ISO 4217
      t.check_constraint "length(currency_code) = 3", name: "countries_currency_code_length"
    end

    create_table :organization_countries do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }
      t.references :country,      null: false, foreign_key: { on_delete: :restrict }
      t.timestamps
      t.index [ :organization_id, :country_id ], unique: true
    end
  end
end
