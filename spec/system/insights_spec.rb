require "rails_helper"

RSpec.describe "Insights", type: :system do
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }

  before do
    engineer = create(:job_role, organization:, name: "Software Engineer")
    accountant = create(:job_role, organization:, name: "Accountant")
    engineering = create(:department, organization:, name: "Engineering")
    finance = create(:department, organization:, name: "Finance")
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
    engineers = create(:pay_structure, organization:, country: india, job_role: engineer, variable_pay_percent_bp: 1_000)
    accountants = create(:pay_structure, organization:, country: india, job_role: accountant, variable_pay_percent_bp: 0)
    { 1_000_000 => engineering, 2_000_000 => engineering }.each do |basic, department|
      create(:employee, pay_structure: engineers, department:, initial_basic_pay: basic, hire_date: Date.new(2024, 4, 1))
    end
    create(:employee, pay_structure: accountants, department: finance, initial_basic_pay: 600_000, hire_date: Date.new(2024, 4, 1))
    sign_in create(:user, organization:)
  end

  it "drills down from the country summary to roles and departments, switching between pay measures" do
    visit root_path
    click_link "Insights"
    click_link "India"

    within(".stats") do
      expect(page).to have_text(/Headcount\s+3/)
      expect(page).to have_text("₹10,00,000")   # median basic
    end

    within("section[aria-label='By job role']") do
      expect(page).to have_css("tr", text: /Software Engineer\s+2\s+₹10,00,000\s+₹15,00,000\s+₹15,00,000\s+₹20,00,000/)
      find("input[aria-label='Total target']").click
      # engineers: gross 14,00,000 / 28,00,000 → total target 15,40,000 / 30,80,000
      expect(page).to have_css("tr", text: /Software Engineer\s+2\s+₹15,40,000\s+₹23,10,000\s+₹23,10,000\s+₹30,80,000/)
    end

    within("section[aria-label='By department']") do
      expect(page).to have_css("tr", text: /Finance\s+1\s+₹6,00,000/)
    end
  end
end
