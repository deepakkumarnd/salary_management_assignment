require "rails_helper"

RSpec.describe Payroll::MonthlyPay do
  let(:organization) { create(:organization, standard_hours_per_week: 40) }
  let(:india) { create(:country, :india) }
  let(:structure) do
    create(:pay_structure, organization:, country: india, variable_pay_percent_bp: 1_000, overtime_percent_bp: 15_000)
  end
  let(:september) { Payroll::Month.parse("2026-09") }   # 30 days

  before { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }   # deductions are entered in the current month

  def employee(hire_date: Date.new(2024, 4, 1), basic: 1_200_000, **attributes)
    create(:employee, pay_structure: structure, hire_date:, initial_basic_pay: basic, **attributes)
  end

  def pay(employee, month = september, deductions: employee.payroll_deductions.where(period_start: month.start).to_a)
    described_class.new(employee:, month:, revisions: employee.salary_revisions.to_a, structure: PayStructure.find(structure.id),
                        country_allowances: organization.country_allowances.to_a, deductions:)
  end

  it "pays a twelfth of the annual amounts for a full month" do
    result = pay(employee)

    expect(result.days_employed).to eq(30)
    expect(result.basic_monthly).to eq(100_000)
    expect(result.allowance_amounts).to eq("HRA" => 40_000)
    expect(result.gross).to eq(140_000)
    expect(result.period_status).to eq("continuing")
  end

  it "prorates a joiner by calendar days" do
    result = pay(employee(hire_date: Date.new(2026, 9, 16)))

    expect(result.days_employed).to eq(15)
    expect(result.basic_monthly).to eq(50_000)   # 12,00,000 × 15 / 360
    expect(result.period_status).to eq("joined")
  end

  it "prorates a leaver by calendar days, rounding each component half up" do
    result = pay(employee(employment_end_date: Date.new(2026, 9, 10), exit_reason: "resignation"))

    expect(result.days_employed).to eq(10)
    expect(result.basic_monthly).to eq(33_333)    # 33,333.33
    expect(result.allowance_amounts["HRA"]).to eq(13_333)
    expect(result.gross).to eq(46_666)             # the rounded components, added up
    expect(result.period_status).to eq("left")
  end

  it "marks someone who joined and left in the month" do
    result = pay(employee(hire_date: Date.new(2026, 9, 5), employment_end_date: Date.new(2026, 9, 25), exit_reason: "end_of_contract"))
    expect(result.period_status).to eq("joined_and_left")
  end

  it "splits the month at a revision (the worked example in the design)" do
    person = employee
    create(:salary_revision, employee: person, effective_on: Date.new(2026, 9, 16), basic_pay: 1_320_000)

    result = pay(person)

    expect(result.basic_monthly).to eq(105_000)   # 12,00,000 × 15/360 + 13,20,000 × 15/360 = 50,000 + 55,000
    expect(result.allowance_amounts["HRA"]).to eq(42_000)
    expect(result.pay_change).to have_attributes(effective_on: Date.new(2026, 9, 16), basic_pay: 1_320_000, previous_basic: 1_200_000)
    expect(result.pay_changes_count).to eq(1)
  end

  it "ignores voided revisions" do
    person = employee
    create(:salary_revision, employee: person, effective_on: Date.new(2026, 9, 16), basic_pay: 9_999_999,
                             voided_at: Time.current, voided_by: create(:user, organization:), void_reason: "Typo")

    expect(pay(person).basic_monthly).to eq(100_000)
    expect(pay(person).pay_change).to be_nil
  end

  describe "month lengths" do
    it "uses the calendar days of each month" do
      jan = Payroll::Month.parse("2026-01")        # 31
      feb = Payroll::Month.parse("2026-02")        # 28
      leap_feb = Payroll::Month.parse("2024-02")   # 29

      expect(pay(employee(hire_date: Date.new(2026, 1, 17)), jan).basic_monthly).to eq(48_387)   # 15/31: 48,387.10
      expect(pay(employee(hire_date: Date.new(2026, 2, 15)), feb).basic_monthly).to eq(50_000)   # 14/28
      expect(pay(employee(hire_date: Date.new(2024, 2, 15)), leap_feb).basic_monthly).to eq(51_724)   # 15/29: 51,724.14
      expect(pay(employee(hire_date: Date.new(2023, 4, 1)), leap_feb).basic_monthly).to eq(100_000)  # full month
    end
  end

  it "always makes the components add up to the gross" do
    person = employee(basic: 1_234_567, hire_date: Date.new(2026, 9, 7))
    create(:pay_structure_allowance, pay_structure: structure, name: "Special", percent_bp: 1_333)
    create(:salary_revision, employee: person, effective_on: Date.new(2026, 9, 19), basic_pay: 1_333_331)

    result = pay(person)

    expect(result.basic_monthly + result.allowance_amounts.values.sum).to eq(result.gross)
    expect(result.allowance_amounts.keys).to eq(%w[HRA Special])   # country first, then role
  end

  describe "deductions" do
    let(:person) { employee }
    let(:user) { create(:user, organization:) }

    it "values unpaid leave at the daily gross rate, including half days" do
      create(:payroll_deduction, :unpaid_leave, employee: person, period_start: september.start, unpaid_half_days: 3)

      result = pay(person)

      # annual gross 16,80,000 / 12 / 30 × 1.5 = 7,000
      expect(result.unpaid_leave_days).to eq(1.5r)
      expect(result.unpaid_leave_deduction).to eq(7_000)
      expect(result.net).to eq(140_000 - 7_000)
    end

    it "uses the gross in force on the last employed day of the month" do
      create(:salary_revision, employee: person, effective_on: Date.new(2026, 9, 16), basic_pay: 1_320_000)
      create(:payroll_deduction, :unpaid_leave, employee: person, period_start: september.start, unpaid_half_days: 2)

      expect(pay(person).unpaid_leave_deduction).to eq(5_133)   # 18,48,000 / 12 / 30 × 1 = 5,133.33
    end

    it "adds up other deductions with their descriptions" do
      create(:payroll_deduction, employee: person, period_start: september.start, amount: 5_000, description: "Salary advance recovery")
      create(:payroll_deduction, employee: person, period_start: september.start, amount: 12_000, description: "Notice shortfall")

      result = pay(person)

      expect(result.other_deductions).to eq(17_000)
      expect(result.other_deductions_detail).to eq("Salary advance recovery: 5000; Notice shortfall: 12000")
      expect(result.net).to eq(140_000 - 17_000)
    end

    it "allows a negative net pay, and flags it" do
      create(:payroll_deduction, employee: person, period_start: september.start, amount: 200_000, description: "Advance")

      result = pay(person)

      expect(result.net).to eq(-60_000)
      expect(result).to be_negative_net
    end
  end

  it "adds arrears to the net" do
    arrears = Payroll::Arrears::Result.new(amount: 2_500, from: Payroll::Month.parse("2026-07"), to: Payroll::Month.parse("2026-08"))
    result = described_class.new(employee: employee, month: september, revisions: Employee.last.salary_revisions.to_a,
                                 structure:, country_allowances: organization.country_allowances.to_a, arrears:)

    expect(result.net).to eq(140_000 + 2_500)
  end

  it "gives the annual reference figures as of the last employed day" do
    result = pay(employee(employment_end_date: Date.new(2026, 9, 10), exit_reason: "resignation"))

    expect(result.annual).to have_attributes(basic: 1_200_000, gross: 1_680_000, variable_target: 168_000)
    expect(result.annual.overtime_hourly).to eq(BigDecimal("865.38"))
  end
end
