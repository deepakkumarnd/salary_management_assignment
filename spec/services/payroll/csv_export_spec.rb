require "rails_helper"
require "csv"

RSpec.describe Payroll::CsvExport do
  let(:organization) { create(:organization, name: "Acme Corp", employee_code_prefix: "ACME") }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:accountant) { create(:job_role, organization:, name: "Accountant") }
  let(:engineering) { create(:department, organization:, name: "Engineering") }
  let(:structure) do
    create(:pay_structure, organization:, country: india, job_role: engineer, variable_pay_percent_bp: 1_000,
                           overtime_percent_bp: 15_000).tap do
      create(:pay_structure_allowance, pay_structure: it, name: "Special", percent_bp: 1_000)
    end
  end
  let(:accountant_structure) { create(:pay_structure, organization:, country: india, job_role: accountant, variable_pay_percent_bp: 0) }
  let(:user) { create(:user, organization:, email: "hr-person@acme.test") }
  let(:september) { Payroll::Month.parse("2026-09") }

  before { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  let!(:priya) do
    create(:employee, pay_structure: structure, department: engineering, full_name: "Priya Nair", email: "priya@acme.test",
                      hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_200_000).tap do
      create(:salary_revision, employee: it, effective_on: Date.new(2026, 9, 16), basic_pay: 1_320_000, reason: "promotion",
                               created_by: user)
      create(:payroll_deduction, :unpaid_leave, employee: it, period_start: september.start, unpaid_half_days: 3, created_by: user)
      create(:payroll_deduction, employee: it, period_start: september.start, amount: 5_000, description: "Salary advance recovery",
                                 created_by: user)
    end
  end
  let!(:rahul) do
    create(:employee, pay_structure: accountant_structure, department: engineering, full_name: "=HYPERLINK(\"http://x\")",
                      email: "rahul@acme.test", hire_date: Date.new(2026, 9, 16), initial_basic_pay: 600_000)
  end

  let(:export) { described_class.new(Payroll::Run.new(organization, india, september)) }
  let(:rows) { CSV.parse(export.to_s.delete_prefix("﻿"), headers: true) }

  it "names the file after the organization, country and month" do
    expect(export.filename).to eq("acme-corp-payroll-india-2026-09.csv")
  end

  it "is UTF-8 with a BOM and CRLF line endings, so it opens cleanly in Excel" do
    expect(export.to_s).to start_with("﻿employee_id,")
    expect(export.to_s.encoding).to eq(Encoding::UTF_8)
    expect(export.to_s.lines.first).to end_with("\r\n")
    expect(export.row_count).to eq(2)
  end

  it "has the columns in order, with one column per allowance: country's first, then roles'" do
    expect(rows.headers).to eq(%w[
      employee_id full_name email department job_role employment_type currency
      hire_date last_working_day exit_reason period_status days_in_month days_employed
      basic_pay_annual gross_pay_annual basic_pay_monthly allowance_hra_monthly allowance_special_monthly gross_pay_monthly
      arrears arrears_from arrears_to unpaid_leave_days unpaid_leave_deduction other_deductions other_deductions_detail
      net_pay_before_tax pay_changes_in_month previous_basic_pay_annual pay_change_effective_on pay_change_reason
      variable_pay_percent target_variable_pay_annual overtime_percent overtime_hourly_rate
    ])
  end

  it "writes the month's amounts as plain numbers, dates as ISO and percentages with two decimals" do
    row = rows.find { it["employee_id"] == priya.employee_code }

    expect(row.to_h).to include(
      "full_name" => "Priya Nair", "department" => "Engineering", "job_role" => "Software Engineer",
      "employment_type" => "full_time", "currency" => "INR", "hire_date" => "2024-04-01", "last_working_day" => nil,
      "period_status" => "continuing", "days_in_month" => "30", "days_employed" => "30",
      "basic_pay_annual" => "1320000", "gross_pay_annual" => "1980000",
      "basic_pay_monthly" => "105000", "allowance_hra_monthly" => "42000", "allowance_special_monthly" => "10500",
      "gross_pay_monthly" => "157500",
      "arrears" => "0", "arrears_from" => nil, "arrears_to" => nil,
      "unpaid_leave_days" => "1.5", "unpaid_leave_deduction" => "8250",     # 19,80,000 / 12 / 30 × 1.5
      "other_deductions" => "5000", "other_deductions_detail" => "Salary advance recovery: 5000",
      "net_pay_before_tax" => (157_500 - 8_250 - 5_000).to_s,
      "pay_changes_in_month" => "1", "previous_basic_pay_annual" => "1200000", "pay_change_effective_on" => "2026-09-16",
      "pay_change_reason" => "promotion",
      "variable_pay_percent" => "10.00", "target_variable_pay_annual" => "198000",
      "overtime_percent" => "150.00", "overtime_hourly_rate" => "951.92"
    )
  end

  it "leaves allowance columns blank where they don't apply to the row's role" do
    row = rows.find { it["employee_id"] == rahul.employee_code }

    expect(row["allowance_special_monthly"]).to be_nil
    expect(row["allowance_hra_monthly"]).to eq("10000")   # 15 of 30 days of 2,40,000 a year
    expect(row["period_status"]).to eq("joined")
    expect(row["pay_changes_in_month"]).to eq("0")
  end

  it "neutralises text that Excel would run as a formula" do
    row = rows.find { it["employee_id"] == rahul.employee_code }
    expect(row["full_name"]).to eq("'=HYPERLINK(\"http://x\")")
  end

  it "keeps negative numbers as numbers" do
    create(:payroll_deduction, employee: rahul, period_start: september.start, amount: 500_000, description: "-Advance",
                               created_by: user)
    row = rows.find { it["employee_id"] == rahul.employee_code }

    expect(row["net_pay_before_tax"]).to match(/\A-\d+\z/)
    expect(row["other_deductions_detail"]).to eq("'-Advance: 500000")
  end

  it "contains employees only, never HR accounts" do
    expect(export.to_s).not_to include(user.email)
  end

  it "has a checksum of the file as downloaded" do
    expect(export.sha256).to eq(Digest::SHA256.hexdigest(export.to_s))
  end
end
