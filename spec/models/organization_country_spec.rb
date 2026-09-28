require "rails_helper"

RSpec.describe OrganizationCountry, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:country) }

  it "can't be removed while the organization has allowances in that country" do
    allowance = create(:country_allowance)
    operating = allowance.organization.organization_countries.find_by!(country: allowance.country)

    expect(operating.destroy).to be(false)
    expect(operating.errors[:base]).to be_present
  end

  it "is removed when no allowances use it" do
    allowance = create(:country_allowance)
    other_organization_country = create(:organization).organization_countries.create!(country: allowance.country)

    expect(other_organization_country.destroy).to be_truthy
  end
end
