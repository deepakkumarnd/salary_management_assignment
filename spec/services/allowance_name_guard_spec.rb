require "rails_helper"

RSpec.describe AllowanceNameGuard do
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer) }

  describe ".conflict_for_role_allowance" do
    it "reports a country allowance with the same name, ignoring case" do
      create(:country_allowance, organization:, country: india, name: "HRA")
      allowance = structure.allowances.build(name: "hra", percent_bp: 1_000)

      expect(described_class.conflict_for_role_allowance(allowance)).to eq("HRA is already a country allowance in India")
    end

    it "allows the name when the country allowance is in another country or organization" do
      create(:country_allowance, organization:, name: "HRA")                           # another country
      create(:country_allowance, country: india, name: "HRA")                          # another organization
      allowance = structure.allowances.build(name: "HRA", percent_bp: 1_000)

      expect(described_class.conflict_for_role_allowance(allowance)).to be_nil
    end
  end

  describe ".conflict_for_country_allowance" do
    it "reports role allowances in that country with the same name, ignoring case" do
      create(:pay_structure_allowance, pay_structure: structure, name: "Special")
      allowance = build(:country_allowance, organization:, country: india, name: "SPECIAL")

      expect(described_class.conflict_for_country_allowance(allowance))
        .to eq("Special is already a role allowance for Software Engineer in India")
    end

    it "lists every role that uses the name" do
      create(:pay_structure_allowance, pay_structure: structure, name: "Special")
      accountant = create(:pay_structure, organization:, country: india,
                                          job_role: create(:job_role, organization:, name: "Accountant"))
      create(:pay_structure_allowance, pay_structure: accountant, name: "Special")
      allowance = build(:country_allowance, organization:, country: india, name: "Special")

      expect(described_class.conflict_for_country_allowance(allowance))
        .to eq("Special is already a role allowance for Accountant and Software Engineer in India")
    end

    it "allows the name when the role allowance is in another country or organization" do
      create(:pay_structure_allowance, pay_structure: create(:pay_structure, organization:), name: "Special")
      create(:pay_structure_allowance, pay_structure: create(:pay_structure, country: india), name: "Special")
      allowance = build(:country_allowance, organization:, country: india, name: "Special")

      expect(described_class.conflict_for_country_allowance(allowance)).to be_nil
    end
  end
end
