require "rails_helper"

RSpec.describe CountryAllowance, type: :model do
  subject(:allowance) { build(:country_allowance) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:country) }
  it { is_expected.to belong_to(:updated_by).class_name("User").optional }
  it { is_expected.to validate_presence_of(:name) }

  describe "percent" do
    it "reads basis points as a percentage with two decimals" do
      expect(build(:country_allowance, percent_bp: 4_000).percent).to eq("40.00")
      expect(build(:country_allowance, percent_bp: 1_250).percent).to eq("12.50")
    end

    it "parses whole and decimal percentages into basis points" do
      { "40" => 4_000, "12.5" => 1_250, "0.01" => 1, " 7.25 % " => 725 }.each do |input, bp|
        allowance.percent = input
        expect(allowance.percent_bp).to eq(bp), "expected #{input.inspect} → #{bp}"
      end
    end

    it "rejects values that aren't a number with at most two decimals" do
      [ "abc", "12.345", "-5", "1e3" ].each do |input|
        allowance.percent = input
        expect(allowance).not_to be_valid, "expected #{input.inspect} to be invalid"
        expect(allowance.errors[:percent]).to include("must be a number with at most 2 decimal places")
      end
    end

    it "must be between 0.01% and 200%" do
      allowance.percent = "0"
      expect(allowance).not_to be_valid
      expect(allowance.errors[:percent]).to include("must be between 0.01 and 200")

      allowance.percent = "200"
      expect(allowance).to be_valid

      allowance.percent = "200.01"
      expect(allowance).not_to be_valid
    end

    it "is required" do
      allowance.percent = ""
      expect(allowance).not_to be_valid
      expect(allowance.errors[:percent]).to include("can't be blank")
    end
  end

  describe "name" do
    it "is unique per organization and country, ignoring case" do
      existing = create(:country_allowance, name: "HRA")

      duplicate = build(:country_allowance, organization: existing.organization, country: existing.country, name: "hra")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "may repeat in another country or another organization" do
      existing = create(:country_allowance, name: "HRA")

      expect(build(:country_allowance, organization: existing.organization, name: "HRA")).to be_valid
      expect(build(:country_allowance, country: existing.country, name: "HRA")).to be_valid
    end
  end

  it "can't reuse the name of a role allowance in the same country" do
    role_allowance = create(:pay_structure_allowance, name: "Special")
    structure = role_allowance.pay_structure

    allowance = build(:country_allowance, organization: structure.organization, country: structure.country, name: "special")

    expect(allowance).not_to be_valid
    expect(allowance.errors[:name])
      .to include("Special is already a role allowance for #{structure.job_role.name} in #{structure.country.name}")
  end

  it "must be for one of the organization's operating countries" do
    allowance = described_class.new(organization: create(:organization), country: create(:country),
                                    name: "HRA", percent: "40")
    expect(allowance).not_to be_valid
    expect(allowance.errors[:country]).to include("is not one of the organization's operating countries")
  end

  it "records who last changed it" do
    user = create(:user)
    Current.set(user:) { allowance.save! }
    expect(allowance.updated_by).to eq(user)
  end
end
