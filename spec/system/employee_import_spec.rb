require "rails_helper"

RSpec.describe "Employee import", type: :system do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization, name: "Acme Corp", employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }

  before do
    engineer = create(:job_role, organization:, name: "Software Engineer")
    create(:department, organization:, name: "Engineering")
    create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_200_000)
    sign_in user
  end

  it "uploads a CSV, follows the import in the background, and shows what was skipped and why" do
    csv = Rails.root.join("tmp/people.csv")
    File.write(csv, <<~CSV)
      name,email,department,designation,basic_pay,country,hire_date,employment_type
      Priya Nair,priya@acme.test,Engineering,Software Engineer,"12,00,000",India,2025-04-01,
      Rahul Verma,rahul@acme.test,Engineering,Data Analyst,900000,India,,
      Anita Rao,not-an-email,Engineering,Software Engineer,900000,India,,
    CSV

    visit employees_path
    click_link "Import"
    click_link "Import employees"
    attach_file "CSV file", csv
    click_button "Upload and import"

    expect(page).to have_text("people.csv was uploaded")
    expect(page).to have_text("Waiting to start")

    perform_enqueued_jobs

    # The page refreshes itself until the import finishes.
    expect(page).to have_css(".badge", text: "Completed", wait: 10)
    expect(page).to have_no_text("Waiting to start")
    within(".stats") { expect(page).to have_text("Imported\n1").and have_text("Skipped\n2") }
    expect(page).to have_text("New job roles: Data Analyst")

    within("section", text: "Pay structures needed") do
      expect(page).to have_text("Data Analyst in India (1 row)")
    end
    within("section", text: "Skipped rows") do
      expect(page).to have_css("tr", text: "Email is invalid")
      expect(page).to have_css("tr", text: "Designation Data Analyst has no pay structure in India yet")
    end

    click_link "Employees", match: :first
    expect(page).to have_text("Priya Nair")
  ensure
    FileUtils.rm_f(csv)
  end
end
