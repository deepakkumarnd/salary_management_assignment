class AddPayDataVersionToOrganizations < ActiveRecord::Migration[8.1]
  def change
    # Bumped whenever pay-related data changes (employees, revisions, pay policy, catalogues); part of the cache key of
    # computed reports, so any change makes them recompute.
    add_column :organizations, :pay_data_version, :integer, null: false, default: 0
  end
end
