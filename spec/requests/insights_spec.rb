require "rails_helper"

RSpec.describe "Insights", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:engineering) { create(:department, organization:, name: "Engineering") }

  before do
    organization.countries << germany
    structure = create(:pay_structure, organization:, country: india, job_role: engineer, variable_pay_percent_bp: 1_000)
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
    [ 1_000_000, 2_000_000 ].each do |basic|
      create(:employee, pay_structure: structure, department: engineering, initial_basic_pay: basic,
                        hire_date: Date.new(2024, 4, 1))
    end
    sign_in user
  end

  describe "GET /insights" do
    it "summarises every operating country in its own currency" do
      get insights_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("India", "INR", "₹10,00,000", "₹20,00,000", "₹15,00,000",   # basic min/max/median
                                       "₹14,00,000", "₹28,00,000",                                  # gross min/max
                                       "₹30,80,000",                                                # total target max
                                       "Total cost to company", "₹46,20,000",                       # 15,40,000 + 30,80,000
                                       "Germany", "No current employees")
    end

    it "is linked from the navigation" do
      get insights_path
      expect(response.body).to include(%(href="#{insights_path}"))
    end
  end

  describe "GET /insights/:country_id" do
    it "breaks the country down by job role and department" do
      get insight_path(india)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Headcount", "Median basic", "₹15,00,000", "Total cost to company", "₹46,20,000",
                                       "By job role", "Software Engineer",
                                       "By department", "Engineering")
    end

    it "returns 404 for a country the organization doesn't operate in" do
      get insight_path(create(:country, name: "Japan", currency_code: "JPY"))
      expect(response).to have_http_status(:not_found)
    end
  end

  it "never includes another organization's employees" do
    create(:employee, pay_structure: create(:pay_structure, country: india, default_basic_pay: 99_999_999),
                      initial_basic_pay: 99_999_999, hire_date: Date.new(2024, 4, 1))

    get insight_path(india)

    expect(response.body).not_to include("9,99,99,999")
  end
end
