require "rails_helper"

RSpec.describe "Employee management", type: :system do
  let(:organization) { create(:organization, name: "Acme Corporation", employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:, full_name: "Deepak Kumar") }
  let(:india) { create(:country, :india) }

  before do
    engineer = create(:job_role, organization:, name: "Software Engineer")
    create(:job_role, organization:, name: "Accountant")
    create(:department, organization:, name: "Engineering")
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
    structure = create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_200_000,
                                       variable_pay_percent_bp: 1_000)
    create(:pay_structure_allowance, pay_structure: structure, name: "Special", percent_bp: 1_500)
    sign_in user
  end

  it "hires with a pre-filled basic and a live breakdown, then revises, corrects, ends and undoes" do
    travel_to Time.utc(2026, 9, 20, 10)

    # Hire: choosing country + role pre-fills the basic and shows the breakdown, labelled Country / Role
    visit employees_path
    click_link "Add employee"
    fill_in "Full name", with: "Priya Nair"
    fill_in "Email", with: "priya@acme.test"
    select "India", from: "Country"
    select "Accountant", from: "Job role"
    expect(page).to have_text("There is no pay structure for Accountant in India yet")
    select "Software Engineer", from: "Job role"
    expect(page).to have_field("Starting basic pay", with: "12,00,000")
    within("#pay_preview") do
      expect(page).to have_css("tr", text: /HRA\s+Country\s+40% of basic\s+₹4,80,000/)
      expect(page).to have_css("tr", text: /Special\s+Role\s+15% of basic\s+₹1,80,000/)
      expect(page).to have_css("tr", text: /Gross pay\s+₹18,60,000/)          # 12,00,000 + 4,80,000 + 1,80,000
      expect(page).to have_css("tr", text: /Total target pay\s+₹20,46,000/)   # gross + 10%
    end
    fill_in "Starting basic pay", with: "10,00,000"
    within("#pay_preview") { expect(page).to have_css("tr", text: /Gross pay\s+₹15,50,000/) }
    select "Engineering", from: "Department"
    fill_in "Hire date", with: Date.new(2024, 4, 1)
    click_button "Add employee"

    expect(page).to have_text("Priya Nair was added as ACME-00001")
    expect(page).to have_current_path("/employees/ACME-00001")
    expect(page).to have_text("₹10,00,000")

    # A backdated raise, with the change and the backdating shown before saving
    click_link "Record salary revision"
    fill_in "Effective date", with: Date.new(2026, 4, 1)
    fill_in "New annual basic pay", with: "11,50,000"
    within("#pay_preview") do
      expect(page).to have_text("+₹1,50,000 (+15.0%)")
      expect(page).to have_text("Backdated")
    end
    click_button "Record revision"
    expect(page).to have_text("backdated to 1 Apr 2026")
    within("tr", text: "1 Apr 2026") do
      expect(page).to have_text("₹11,50,000")
      expect(page).to have_text("Backdated")
    end

    # It should have been 11,00,000: correct it
    within("tr", text: "1 Apr 2026") { click_link "Correct" }
    fill_in "New annual basic pay", with: "11,00,000"
    fill_in "Why is the original wrong?", with: "Typed 11,50,000 instead of 11,00,000"
    click_button "Save correction"
    expect(page).to have_text("The revision was corrected")
    expect(page).to have_css("tr.opacity-60", text: "Typed 11,50,000 instead of 11,00,000")
    expect(page).to have_text("+₹1,00,000 (+10.0%)")

    # End employment: Leaving until the last working day, then Exited and read-only
    click_link "End employment"
    fill_in "Last working day", with: Date.new(2026, 10, 31)
    select "Resignation", from: "Reason"
    click_button "Record exit"
    expect(page).to have_text("Priya Nair is leaving")
    expect(page).to have_text("Leaving (until 31 Oct)")

    travel_to Time.utc(2026, 11, 1, 10)
    Capybara.reset_session!   # six weeks later the 30-minute session has long timed out: start a fresh one
    sign_in user
    visit employee_path("ACME-00001")
    expect(page).to have_text("Exited")
    expect(page).to have_no_link("Record salary revision")
    expect(page).to have_no_link("Edit")
    expect(page).to have_text("Annual pay as of 31 Oct 2026 (last working day)")

    accept_confirm { click_button "Undo exit" }
    expect(page).to have_text("The exit was undone")
    expect(page).to have_css(".badge", text: "Active")
  ensure
    travel_back
  end

  it "shows another user's edit as a conflict and lets the user re-apply" do
    employee = create(:employee, pay_structure: PayStructure.sole, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1))
    colleague = create(:user, organization:, full_name: "Anita Rao")

    visit edit_employee_path(employee)
    fill_in "Full name", with: "Priya N."
    Current.set(user: colleague) { Employee.find(employee.id).update!(full_name: "Priya Nair-Menon") }
    click_button "Save changes"

    expect(page).to have_text("Anita Rao changed this employee")
    expect(page).to have_text("Saved value: Priya Nair-Menon")
    expect(page).to have_field("Full name", with: "Priya N.")

    click_button "Save changes"
    expect(page).to have_text("Priya N. was updated")
  end
end
