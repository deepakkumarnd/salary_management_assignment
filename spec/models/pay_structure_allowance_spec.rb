require "rails_helper"

RSpec.describe PayStructureAllowance, type: :model do
  subject(:allowance) { build(:pay_structure_allowance) }

  it { is_expected.to belong_to(:pay_structure) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(40) }

  it "is unique within its structure, ignoring case" do
    existing = create(:pay_structure_allowance, name: "Special")

    expect(build(:pay_structure_allowance, pay_structure: existing.pay_structure, name: "special")).not_to be_valid
    expect(build(:pay_structure_allowance, name: "Special")).to be_valid
  end

  it "takes a percentage between 0.01% and 200%" do
    allowance.percent = "15"
    expect(allowance.percent_bp).to eq(1_500)
    allowance.percent = "0"
    expect(allowance).not_to be_valid
    expect(allowance.errors[:percent]).to include("must be between 0.01 and 200")
  end

  it "can't reuse the name of a country allowance in the same country" do
    structure = create(:pay_structure)
    create(:country_allowance, organization: structure.organization, country: structure.country, name: "HRA")

    allowance = build(:pay_structure_allowance, pay_structure: structure, name: "hra")

    expect(allowance).not_to be_valid
    expect(allowance.errors[:name]).to include("HRA is already a country allowance in #{structure.country.name}")
  end
end
