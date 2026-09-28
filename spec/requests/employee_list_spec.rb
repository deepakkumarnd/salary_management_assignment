require "rails_helper"

RSpec.describe "Employee list", type: :request do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer) }

  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  def hire(count, **attributes)
    Array.new(count) { create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), **attributes) }
  end

  it "shows 25 per page with a result count, and pages through" do
    hire(27)

    get employees_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("1–25 of 27", "ACME-00025")
    expect(response.body).not_to include("ACME-00026")

    get employees_path(page: 2)
    expect(response.body).to include("26–27 of 27", "ACME-00027")
    expect(response.body).not_to include("ACME-00025")
  end

  it "shows an empty page, not an error, past the last page" do
    hire(1)
    get employees_path(page: 9)
    expect(response).to have_http_status(:ok)
  end

  it "applies search, filters and sorting from the URL" do
    priya = hire(1, full_name: "Priya Nair").first
    hire(1, full_name: "Anna Schmidt")

    get employees_path(q: "priya", country_id: india.id, job_role_id: engineer.id, sort: "full_name", dir: "desc")

    expect(response.body).to include(priya.employee_code)
    expect(response.body).not_to include("Anna Schmidt")
    expect(response.body).to include("1–1 of 1")
  end

  it "shows a badge per active filter, each linking to the list without it" do
    hire(1, full_name: "Priya Nair")

    get employees_path(q: "priya", country_id: india.id)

    expect(response.body).to include("“priya”", "India", "Clear all")
    expect(response.body).to include(%(href="/employees?country_id=#{india.id}"))   # removes the search, keeps the country
  end

  it "keeps the search when sorting and paging" do
    hire(1, full_name: "Priya Nair")

    get employees_path(q: "priya")

    expect(response.body).to include("/employees?q=priya&amp;sort=full_name")   # Name header: ascending first
    expect(response.body).to include("/employees?dir=desc&amp;q=priya")        # Employee ID header: already sorted, so flips
  end

  it "explains an empty result and offers to clear the filters" do
    hire(1, full_name: "Priya Nair")

    get employees_path(q: "nobody", country_id: india.id, job_role_id: engineer.id)

    expect(response.body).to include("No employees match “nobody” in India · Software Engineer", "Clear filters")
  end

  it "only offers the organization's own countries, departments and roles as filters" do
    create(:department, name: "Somebody Else's Department")
    get employees_path
    expect(response.body).not_to include("Somebody Else&#39;s Department")
  end
end
