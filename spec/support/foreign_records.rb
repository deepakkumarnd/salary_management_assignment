# Records that belong to another organization, for tenant-isolation specs. The other organization uses a different
# employee ID prefix, so its codes (GLBX-00001) never coincide with the signed-in organization's (ACME-00001).
module ForeignRecords
  def create_foreign_employee(country: create(:country), **attributes)
    organization = create(:organization, name: "Globex", employee_code_prefix: "GLBX")
    create(:employee, pay_structure: create(:pay_structure, organization:, country:), **attributes)
  end
end

RSpec.configure { |config| config.include ForeignRecords, type: :request }
