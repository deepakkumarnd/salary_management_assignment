require "rails_helper"

RSpec.describe Organization, type: :model do
  subject(:organization) { build(:organization) }

  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:organization_countries).dependent(:destroy) }
    it { is_expected.to have_many(:countries).through(:organization_countries) }
    it { is_expected.to have_many(:departments) }
    it { is_expected.to have_many(:job_roles) }
    it { is_expected.to have_many(:country_allowances) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_numericality_of(:standard_hours_per_week).only_integer.is_in(1..80) }

    it "accepts a prefix of 2 to 6 uppercase letters" do
      %w[AB ACME GLOBEX].each do |prefix|
        organization.employee_code_prefix = prefix
        expect(organization).to be_valid, "expected #{prefix} to be valid"
      end
    end

    it "rejects prefixes that are too short, too long or not letters" do
      [ "A", "ACMECOR", "AC1", "AC-ME", "ÄCME" ].each do |prefix|
        organization.employee_code_prefix = prefix
        expect(organization).not_to be_valid, "expected #{prefix} to be invalid"
        expect(organization.errors[:employee_code_prefix]).to include("must be 2 to 6 letters, A to Z")
      end
    end
  end

  describe "employee code prefix" do
    it "is stripped and upper-cased" do
      organization.employee_code_prefix = "  acme "
      expect(organization.employee_code_prefix).to eq("ACME")
    end

    it "is suggested from the name when left blank" do
      organization = build(:organization, name: "Acme Corp", employee_code_prefix: "")
      organization.validate
      expect(organization.employee_code_prefix).to eq("ACME")
    end

    it "is kept when given" do
      organization = build(:organization, name: "Acme Corp", employee_code_prefix: "AC")
      organization.validate
      expect(organization.employee_code_prefix).to eq("AC")
    end
  end

  describe ".suggested_code_prefix" do
    it "uses the first word, up to 6 letters" do
      expect(described_class.suggested_code_prefix("Acme Corp")).to eq("ACME")
      expect(described_class.suggested_code_prefix("Globex International")).to eq("GLOBEX")
      expect(described_class.suggested_code_prefix("Initech")).to eq("INITEC")
    end

    it "falls back to initials when the first word is a single letter" do
      expect(described_class.suggested_code_prefix("X Ray Labs")).to eq("XRL")
    end

    it "returns nil when no suggestion is possible" do
      expect(described_class.suggested_code_prefix("")).to be_nil
      expect(described_class.suggested_code_prefix("3M")).to be_nil
    end
  end

  describe "#setup_completed?" do
    it "is true once setup_completed_at is set" do
      expect(build(:organization)).to be_setup_completed
      expect(build(:organization, :pending_setup)).not_to be_setup_completed
    end
  end

  describe "#update_operating_countries" do
    let(:organization) { create(:organization, :pending_setup) }
    let(:india) { create(:country, :india) }
    let(:germany) { create(:country, :germany) }

    it "adds the chosen countries" do
      expect(organization.update_operating_countries([ india.id, germany.id ])).to be(true)
      expect(organization.reload.countries).to contain_exactly(india, germany)
    end

    it "removes countries that are no longer chosen" do
      organization.countries << india << germany

      organization.update_operating_countries([ india.id.to_s ])

      expect(organization.reload.countries).to contain_exactly(india)
    end

    it "requires at least one country" do
      expect(organization.update_operating_countries([ "" ])).to be(false)
      expect(organization.errors[:countries]).to include("choose at least one country")
    end

    it "ignores unknown ids" do
      organization.update_operating_countries([ india.id, 0 ])
      expect(organization.reload.countries).to contain_exactly(india)
    end

    it "refuses to remove a country that still has allowances, and changes nothing" do
      create(:country_allowance, organization:, country: india)
      organization.countries << germany

      expect(organization.update_operating_countries([ germany.id ])).to be(false)
      expect(organization.errors[:base]).to include("India can't be removed while it has allowances or pay structures")
      expect(organization.reload.countries).to contain_exactly(india, germany)
    end
  end

  describe "country allowances (nested)" do
    let(:organization) { create(:organization, :pending_setup) }
    let(:india) { create(:country, :india) }

    before { organization.countries << india }

    it "creates allowances from nested attributes" do
      organization.update!(country_allowances_attributes: [ { country_id: india.id, name: "HRA", percent: "40" } ])
      expect(organization.country_allowances.pluck(:name, :percent_bp)).to eq([ [ "HRA", 4_000 ] ])
    end

    it "ignores blank rows" do
      organization.update!(country_allowances_attributes: [ { country_id: india.id, name: "", percent: "" } ])
      expect(organization.country_allowances).to be_empty
    end

    it "rejects the same name twice for a country in one submission, ignoring case" do
      result = organization.update(country_allowances_attributes: [
        { country_id: india.id, name: "HRA", percent: "40" },
        { country_id: india.id, name: "hra", percent: "10" }
      ])

      expect(result).to be(false)
      expect(organization.errors[:base]).to include("HRA is listed more than once for India")
      expect(organization.country_allowances.reload).to be_empty
    end
  end
end
