require "rails_helper"

RSpec.describe Payroll::Arrears do
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:structure) { create(:pay_structure, organization:, country: india) }
  let(:user) { create(:user, organization:) }
  let(:september) { Payroll::Month.parse("2026-09") }
  let(:august_export_at) { Time.utc(2026, 8, 25, 12) }

  # Hired long ago on 12,00,000 (no allowances: gross = basic, so a raise of 1,20,000 a year is 10,000 a month).
  let!(:employee) do
    travel_to(Time.utc(2024, 4, 1, 9)) do
      create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_200_000)
    end
  end

  def record(at:, effective_on:, basic:)
    travel_to(at) { create(:salary_revision, employee:, effective_on:, basic_pay: basic, created_by: user) }
  end

  def export(month, at:)
    travel_to(at) { create(:payroll_export, organization:, country: india, period_start: month.start, exported_by: user) }
  end

  # Payroll went live in January: months from then on were sent through this system.
  before { export(Payroll::Month.parse("2026-01"), at: Time.utc(2026, 1, 26)) }

  def arrears(month = september)
    calculator = described_class.new(organization:, country: india, month:)
    calculator.for(employee:, revisions: employee.salary_revisions.reload.to_a, structure: PayStructure.find(structure.id),
                   country_allowances: [])
  end

  describe "cutoff" do
    it "is the previous month's latest export" do
      export(september.previous, at: Time.utc(2026, 8, 20))
      export(september.previous, at: august_export_at)

      calculator = described_class.new(organization:, country: india, month: september)
      expect(calculator.cutoff).to eq(august_export_at)
      expect(calculator).to be_previous_month_exported
    end

    it "is the start of the month when the previous month was never exported" do
      calculator = described_class.new(organization:, country: india, month: september)
      expect(calculator.cutoff).to eq(Time.utc(2026, 9, 1))
      expect(calculator).not_to be_previous_month_exported
    end

    it "ignores exports of other countries and organizations" do
      PayrollExport.delete_all
      create(:payroll_export, organization:, period_start: september.previous.start)
      create(:payroll_export, country: india, period_start: september.previous.start)
      expect(described_class.new(organization:, country: india, month: september)).not_to be_previous_month_exported
    end
  end

  it "pays a backdated raise for every earlier month from its effective date" do
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2026, 4, 1), basic: 1_320_000)

    result = arrears

    expect(result.amount).to eq(5 * 10_000)   # April to August
    expect([ result.from, result.to ]).to eq([ Payroll::Month.parse("2026-04"), Payroll::Month.parse("2026-08") ])
  end

  it "prorates arrears for a raise effective mid-month" do
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2026, 8, 17), basic: 1_320_000)   # 15 of August's 31 days

    expect(arrears.amount).to eq(4_839)   # 1,15,000 − 1,00,000 = 15 days × 1,20,000 / 372 → 4,838.71
  end

  it "recovers a raise that was voided after it was paid" do
    raise_revision = record(at: Time.utc(2026, 7, 5), effective_on: Date.new(2026, 7, 1), basic: 1_320_000)
    export(september.previous, at: august_export_at)
    travel_to(Time.utc(2026, 9, 5)) { SalaryRevisions::Void.new(raise_revision, by: user, reason: "Not approved").call }

    expect(arrears.amount).to eq(-2 * 10_000)   # July and August
  end

  it "includes a revision recorded after last month's export but effective last month" do
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 8, 28), effective_on: Date.new(2026, 8, 1), basic: 1_320_000)

    expect(arrears.amount).to eq(10_000)
  end

  it "doesn't repeat revisions recorded before the cutoff (already paid)" do
    record(at: Time.utc(2026, 8, 10), effective_on: Date.new(2026, 6, 1), basic: 1_320_000)
    export(september.previous, at: august_export_at)

    expect(arrears).to eq(described_class::NONE)
  end

  it "measures from the start of the month when the previous month was never exported" do
    record(at: Time.utc(2026, 8, 30), effective_on: Date.new(2026, 6, 1), basic: 1_320_000)   # before 1 Sep: not arrears
    expect(arrears).to eq(described_class::NONE)

    record(at: Time.utc(2026, 9, 3), effective_on: Date.new(2026, 8, 1), basic: 1_440_000)    # after 1 Sep: arrears
    expect(arrears.amount).to eq(10_000)
  end

  it "ignores revisions effective this month or later (they're in this month's pay)" do
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2026, 9, 1), basic: 1_320_000)
    record(at: Time.utc(2026, 9, 11), effective_on: Date.new(2027, 4, 1), basic: 1_500_000)

    expect(arrears).to eq(described_class::NONE)
  end

  it "never creates arrears from a policy change" do
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2026, 8, 1), basic: 1_320_000)
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)

    calculator = described_class.new(organization:, country: india, month: september)
    result = calculator.for(employee:, revisions: employee.salary_revisions.to_a, structure: PayStructure.find(structure.id),
                            country_allowances: organization.country_allowances.to_a)

    expect(result.amount).to eq(14_000)   # the raise, with HRA on both sides: 10,000 + 40% of it
  end

  it "never goes back before the country's first export (e.g. people loaded at go-live)" do
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2025, 11, 1), basic: 1_320_000)   # effective before go-live
    expect(arrears.amount).to eq(8 * 10_000)   # January to August only

    PayrollExport.delete_all
    expect(arrears).to eq(described_class::NONE)   # nothing was ever sent: nothing to correct
  end

  it "only counts months the employee was employed in" do
    travel_to(Time.utc(2026, 7, 1)) { employee.update!(employment_end_date: Date.new(2026, 6, 30), exit_reason: "resignation") }
    export(september.previous, at: august_export_at)
    record(at: Time.utc(2026, 9, 10), effective_on: Date.new(2026, 4, 1), basic: 1_320_000)

    result = arrears

    expect(result.amount).to eq(3 * 10_000)   # April to June; not July or August
    expect(result.to).to eq(Payroll::Month.parse("2026-06"))
  end
end
