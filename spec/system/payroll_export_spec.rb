require "rails_helper"
require "csv"

RSpec.describe "Deductions and payroll export", type: :system do
  let(:organization) { create(:organization, name: "Acme Corp") }
  let(:india) { create(:country, :india) }
  let(:user) { create(:user, organization:) }

  before do
    engineer = create(:job_role, organization:, name: "Software Engineer")
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
    structure = create(:pay_structure, organization:, country: india, job_role: engineer)
    create(:employee, pay_structure: structure, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_200_000)
    create(:employee, pay_structure: structure, full_name: "Rahul Verma", hire_date: Date.new(2024, 4, 1), initial_basic_pay: 600_000)
    sign_in user
  end

  def downloaded_csv
    path = nil
    Timeout.timeout(10) { sleep 0.1 until (path = Dir[File.join(DOWNLOAD_DIR, "*.csv")].first) }
    CSV.parse(File.read(path, encoding: "bom|utf-8"), headers: true).index_by { it["employee_name"] }
  end

  it "enters a month's deductions row by row, then downloads a file with the right amounts" do
    travel_to Time.utc(2026, 9, 28, 10)
    visit root_path
    click_link "Deductions"
    expect(page).to have_text("Deductions · September 2026")

    within("tr", text: "Priya Nair") do
      fill_in "Unpaid days, Priya Nair, September 2026", with: "1.5"
      click_button "Save unpaid days"
    end
    expect(page).to have_css("[role=status]", text: "1.5 unpaid days (1 person)")   # totals update in place

    within("tr", text: "Rahul Verma") do
      fill_in "New deduction amount, Rahul Verma, September 2026", with: "5,000"
      fill_in "New deduction description, Rahul Verma, September 2026", with: "Salary advance recovery"
      click_button "Add deduction"
      expect(page).to have_field(with: "Salary advance recovery")
    end
    expect(page).to have_css("[role=status]", text: "₹5,000 other deductions (1 person)")

    # The browser already refuses more unpaid days than days employed (the server checks too: request specs)
    expect(find_field("Unpaid days, Rahul Verma, September 2026")[:max]).to eq("30")

    click_link "Payroll export for September 2026"
    expect(page).to have_text("India payroll · September 2026")
    within("[aria-label=Money]") do
      expect(page).to have_text("₹2,10,000")   # gross: 1,40,000 + 70,000
      expect(page).to have_text("₹12,000")     # deductions: 7,000 unpaid leave + 5,000
      expect(page).to have_text("₹1,98,000")   # net
    end

    click_button "Download CSV"
    rows = downloaded_csv

    expect(rows["Priya Nair"].to_h).to eq("employee_id" => "ACME-00001", "employee_name" => "Priya Nair",
                                          "gross_salary" => "140000", "deductions" => "7000", "net_salary" => "133000")
    expect(rows["Rahul Verma"].to_h).to include("gross_salary" => "70000", "deductions" => "5000", "net_salary" => "65000")

    visit payroll_exports_path
    within("section[aria-labelledby=export-log]") do
      expect(page).to have_text("September 2026")
      expect(page).to have_text(user.full_name)
    end
  ensure
    travel_back
  end
end
