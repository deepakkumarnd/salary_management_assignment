require "rails_helper"

RSpec.describe Payroll::Run do
  let(:organization) { create(:organization, name: "Acme Corp") }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:accountant) { create(:job_role, organization:, name: "Accountant") }
  let(:structure) do
    create(:pay_structure, organization:, country: india, job_role: engineer, variable_pay_percent_bp: 1_000).tap do
      create(:pay_structure_allowance, pay_structure: it, name: "Special", percent_bp: 1_000)
    end
  end
  let(:accountant_structure) { create(:pay_structure, organization:, country: india, job_role: accountant) }
  let(:user) { create(:user, organization:) }
  let(:september) { Payroll::Month.parse("2026-09") }

  before { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  def hire(name, structure: self.structure, hire_date: Date.new(2024, 4, 1), end_date: nil, exit_reason: "resignation", basic: 1_200_000)
    create(:employee, pay_structure: structure, full_name: name, hire_date:, initial_basic_pay: basic).tap do
      it.update!(employment_end_date: end_date, exit_reason:) if end_date
    end
  end

  def run = described_class.new(organization, india, september)

  describe "roster" do
    it "includes everyone employed on any day of the month, and nobody else" do
      continuing = hire("Continuing")
      joiner = hire("Joiner", hire_date: Date.new(2026, 9, 20))
      leaver = hire("Leaver", end_date: Date.new(2026, 9, 5))
      on_notice = hire("On Notice", end_date: Date.new(2026, 10, 31))
      in_and_out = hire("In And Out", hire_date: Date.new(2026, 9, 2), end_date: Date.new(2026, 9, 12))
      hire("Left In August", end_date: Date.new(2026, 8, 31))
      hire("Mistake", end_date: Date.new(2026, 9, 15), exit_reason: "recorded_in_error")
      create(:employee, pay_structure: create(:pay_structure, organization:, country: germany, job_role: engineer))
      create(:employee, pay_structure: create(:pay_structure, country: india), hire_date: Date.new(2024, 1, 1))   # other org

      expect(run.lines.map(&:employee)).to eq([ continuing, joiner, leaver, on_notice, in_and_out ])
      expect(run.lines.map(&:period_status)).to eq(%w[continuing joined left continuing joined_and_left])
    end
  end

  describe "summary" do
    it "counts people and adds up the money" do
      hire("Continuing")                                                       # gross 1,50,000
      priya = hire("Raised")
      create(:salary_revision, employee: priya, effective_on: Date.new(2026, 9, 16), basic_pay: 1_320_000)
      hire("Joiner", hire_date: Date.new(2026, 9, 16))                         # half a month: 75,000
      leaver = hire("Leaver", end_date: Date.new(2026, 9, 15))                 # half a month: 75,000
      create(:payroll_deduction, employee: leaver, period_start: september.start, amount: 5_000, description: "Advance",
                                 created_by: user)

      summary = run.summary

      expect(summary).to have_attributes(headcount: 4, joiners: 1, leavers: 1, pay_changes: 1)
      expect(summary.gross).to eq(150_000 + 157_500 + 75_000 + 75_000)
      expect(summary.other_deductions).to eq(5_000)
      expect(summary.deductions).to eq(5_000)
      expect(summary.net).to eq(summary.gross - 5_000)
    end
  end

  describe "warnings" do
    it "flags negative net pay, naming the people" do
      person = hire("Big Advance")
      create(:payroll_deduction, employee: person, period_start: september.start, amount: 500_000, description: "Advance",
                                 created_by: user)

      expect(run.warnings.map(&:message)).to include("1 row has a negative net salary")
      expect(run.warnings.find { it.message.include?("negative") }.employees).to eq([ person ])
    end

    it "says when the data changed since this month was last exported" do
      hire("Someone")
      create(:payroll_export, organization:, country: india, period_start: september.start, exported_by: user,
                              sha256: Payroll::CsvExport.new(run).sha256)
      expect(run.warnings.map(&:message)).not_to include(a_string_including("changed since"))

      hire("Someone Else")

      expect(run.warnings.map(&:message)).to include(a_string_including("changed since September 2026 was last exported"))
    end
  end
end
