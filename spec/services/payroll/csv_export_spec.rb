require "rails_helper"
require "csv"

RSpec.describe Payroll::CsvExport do
  let(:organization) { create(:organization, name: "Acme Corp", employee_code_prefix: "ACME") }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer) }
  let(:user) { create(:user, organization:, email: "hr-person@acme.test") }
  let(:september) { Payroll::Month.parse("2026-09") }

  before { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  let!(:priya) do
    create(:employee, pay_structure: structure, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1),
                      initial_basic_pay: 1_200_000).tap do
      create(:payroll_deduction, :unpaid_leave, employee: it, period_start: september.start, unpaid_half_days: 3, created_by: user)
      create(:payroll_deduction, employee: it, period_start: september.start, amount: 5_000, description: "Salary advance recovery",
                                 created_by: user)
    end
  end
  let!(:rahul) do
    create(:employee, pay_structure: structure, full_name: "=HYPERLINK(\"http://x\")", hire_date: Date.new(2026, 9, 16),
                      initial_basic_pay: 600_000)
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

  it "has five columns: employee ID, name, gross salary, deductions and net salary" do
    expect(rows.headers).to eq(%w[employee_id employee_name gross_salary deductions net_salary])
  end

  it "writes the month's amounts as plain numbers, with net = gross − deductions" do
    row = rows.find { it["employee_id"] == priya.employee_code }

    # gross 1,40,000 (basic 1,00,000 + HRA 40,000); deductions 7,000 unpaid leave (1.5 days) + 5,000 advance
    expect(row.to_h).to eq("employee_id" => priya.employee_code, "employee_name" => "Priya Nair",
                           "gross_salary" => "140000", "deductions" => "12000", "net_salary" => "128000")
  end

  it "prorates a joiner's gross by calendar days" do
    row = rows.find { it["employee_id"] == rahul.employee_code }
    expect(row.to_h).to include("gross_salary" => "35000", "deductions" => "0", "net_salary" => "35000")   # 15 of 30 days
  end

  it "neutralises text that Excel would run as a formula" do
    row = rows.find { it["employee_id"] == rahul.employee_code }
    expect(row["employee_name"]).to eq("'=HYPERLINK(\"http://x\")")
  end

  it "keeps a negative net salary as a number" do
    create(:payroll_deduction, employee: rahul, period_start: september.start, amount: 500_000, description: "Advance",
                               created_by: user)
    row = rows.find { it["employee_id"] == rahul.employee_code }

    expect(row["net_salary"]).to eq("-465000")
  end

  it "contains employees only, never HR accounts" do
    expect(export.to_s).not_to include(user.email)
  end

  it "has a checksum of the file as downloaded" do
    expect(export.sha256).to eq(Digest::SHA256.hexdigest(export.to_s))
  end
end
