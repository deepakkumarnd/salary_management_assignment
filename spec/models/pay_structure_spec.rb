require "rails_helper"

RSpec.describe PayStructure, type: :model do
  subject(:structure) { build(:pay_structure) }

  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }

  describe "associations" do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:country) }
    it { is_expected.to belong_to(:job_role) }
    it { is_expected.to belong_to(:updated_by).class_name("User").optional }
    it { is_expected.to have_many(:allowances).class_name("PayStructureAllowance").dependent(:destroy) }
  end

  describe "default basic pay" do
    it "must be a positive whole number" do
      [ 0, -5, "12.5", "abc", "" ].each do |value|
        structure.default_basic_pay = value
        expect(structure).not_to be_valid, "expected #{value.inspect} to be invalid"
        expect(structure.errors[:default_basic_pay]).to be_present
      end
    end

    it "accepts thousands separators as typed in any locale" do
      { "12,00,000" => 1_200_000, "1,200,000" => 1_200_000, "65 000" => 65_000, "65_000" => 65_000 }.each do |input, value|
        structure.default_basic_pay = input
        expect(structure.default_basic_pay).to eq(value), "expected #{input.inspect} → #{value}"
      end
    end

    it "has a sane upper bound" do
      structure.default_basic_pay = 10**12
      expect(structure).not_to be_valid
    end
  end

  describe "percentages" do
    it "accepts variable pay from 0% to 200%" do
      structure.variable_pay_percent = "0"
      expect(structure).to be_valid
      structure.variable_pay_percent = "200"
      expect(structure).to be_valid
      structure.variable_pay_percent = "200.01"
      expect(structure).not_to be_valid
      expect(structure.errors[:variable_pay_percent]).to include("must be between 0 and 200")
    end

    it "accepts overtime from 0% to 400%" do
      structure.overtime_percent = "150"
      expect(structure.overtime_percent_bp).to eq(15_000)
      structure.overtime_percent = "400.01"
      expect(structure).not_to be_valid
      expect(structure.errors[:overtime_percent]).to include("must be between 0 and 400")
    end
  end

  describe "one structure per country and role" do
    it "rejects a second structure for the same country and role" do
      create(:pay_structure, organization:, country: india, job_role: engineer)
      duplicate = build(:pay_structure, organization:, country: india, job_role: engineer)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:job_role]).to include("already has a pay structure in India")
    end

    it "allows the same role in another country" do
      create(:pay_structure, organization:, country: india, job_role: engineer)
      expect(build(:pay_structure, organization:, job_role: engineer)).to be_valid
    end
  end

  it "must be for an operating country" do
    structure = described_class.new(organization:, country: create(:country), job_role: engineer,
                                    default_basic_pay: 100, overtime_percent: "150")
    expect(structure).not_to be_valid
    expect(structure.errors[:country]).to include("is not one of the organization's operating countries")
  end

  it "rejects a job role from another organization" do
    structure = build(:pay_structure, organization:, job_role: create(:job_role))
    expect(structure).not_to be_valid
    expect(structure.errors[:job_role]).to include("must belong to the same organization")
  end

  describe "role allowances (nested)" do
    let(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer) }

    it "saves allowances from nested attributes and ignores blank rows" do
      structure.update!(allowances_attributes: [ { name: "Special", percent: "15" }, { name: "", percent: "" } ])
      expect(structure.allowances.pluck(:name, :percent_bp)).to eq([ [ "Special", 1_500 ] ])
    end

    it "rejects the same name twice in one submission, ignoring case" do
      result = structure.update(allowances_attributes: [ { name: "Special", percent: "15" }, { name: "SPECIAL", percent: "5" } ])

      expect(result).to be(false)
      expect(structure.errors[:base]).to include("Special is listed more than once")
      expect(structure.allowances.reload).to be_empty
    end

    it "bumps the version when only an allowance changes, so concurrent edits conflict" do
      allowance = create(:pay_structure_allowance, pay_structure: structure, percent_bp: 1_500)
      stale = described_class.find(structure.id)

      structure.update!(allowances_attributes: [ { id: allowance.id, percent: "20" } ])
      expect(structure.reload.lock_version).to eq(1)

      expect { stale.update(allowances_attributes: [ { id: allowance.id, percent: "25" } ]) }
        .to raise_error(ActiveRecord::StaleObjectError)
      expect(allowance.reload.percent_bp).to eq(2_000)
    end
  end

  it "records who last changed it" do
    user = create(:user)
    Current.set(user:) { structure.save! }
    expect(structure.updated_by).to eq(user)
  end

  describe "#breakdown_for" do
    it "combines the country's allowances with the role's" do
      organization.update!(standard_hours_per_week: 40)
      create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
      structure = create(:pay_structure, organization:, country: india, job_role: engineer,
                                         variable_pay_percent_bp: 1_000, overtime_percent_bp: 15_000)
      create(:pay_structure_allowance, pay_structure: structure, name: "Special", percent_bp: 1_500)

      result = structure.breakdown_for(1_200_000)

      expect(result.allowances.map { it.values_at(:name, :source, :amount) })
        .to eq([ [ "HRA", :country, 480_000 ], [ "Special", :role, 180_000 ] ])
      expect(result.gross).to eq(1_860_000)
      expect(result.variable_target).to eq(186_000)
      expect(result.total_target).to eq(2_046_000)
    end
  end
end
