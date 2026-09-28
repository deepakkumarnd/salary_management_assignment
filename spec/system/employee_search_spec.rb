require "rails_helper"

RSpec.describe "Employee search", type: :system do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }

  before do
    engineer = create(:job_role, organization:, name: "Software Engineer")
    india_structure = create(:pay_structure, organization:, country: india, job_role: engineer)
    germany_structure = create(:pay_structure, organization:, country: germany, job_role: engineer)
    create(:employee, pay_structure: india_structure, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1))
    create(:employee, pay_structure: germany_structure, full_name: "Anna Schmidt", hire_date: Date.new(2024, 4, 1))
    27.times { |i| create(:employee, pay_structure: india_structure, full_name: "Person #{i + 1}", hire_date: Date.new(2024, 4, 1)) }
    sign_in create(:user, organization:)
  end

  it "searches as you type, filters, sorts and pages, keeping it all in the URL" do
    visit employees_path
    expect(page).to have_text("1–25 of 29")

    # Typing searches after a short pause, and the URL follows
    fill_in "Search by name, email or employee ID", with: "priya"
    expect(page).to have_text("1–1 of 1")
    expect(page).to have_css("td", text: "Priya Nair")
    expect(page).to have_current_path(employees_path(q: "priya"))
    expect(page).to have_css(".badge", text: "“priya”")

    # Choosing a filter applies straight away and combines with the search
    select "Germany", from: "Country"
    expect(page).to have_text("No employees match “priya” in Germany")

    # Back returns to the previous search
    page.go_back
    expect(page).to have_css("td", text: "Priya Nair")

    # Clearing, then sorting by name and paging within the results
    click_link "Clear all"
    expect(page).to have_text("1–25 of 29")
    click_link "Name"
    expect(page).to have_current_path(employees_path(sort: "full_name"))
    expect(first("tbody tr")).to have_text("Anna Schmidt")
    within("nav[aria-label='Pages']") { click_link "2" }
    expect(page).to have_text("26–29 of 29")
    expect(page).to have_current_path(/page=2/)
    expect(Rack::Utils.parse_query(URI(page.current_url).query)).to eq("sort" => "full_name", "page" => "2")
    expect(page).to have_css("td", text: "Priya Nair")
  end
end
