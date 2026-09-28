require "rails_helper"

RSpec.describe "Pay policy (countries)", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }
  let!(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let!(:accountant) { create(:job_role, organization:, name: "Accountant") }

  before do
    organization.countries << india << germany
    sign_in user
  end

  describe "GET /countries" do
    it "lists the operating countries with their allowance and structure counts" do
      create(:country_allowance, organization:, country: india, name: "HRA")
      create(:pay_structure, organization:, country: india, job_role: engineer)

      get countries_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("India", "Germany", "INR", "1 of 2 roles")
    end

    it "is linked from the navigation" do
      get countries_path
      expect(response.body).to include(%(href="#{countries_path}"))
    end
  end

  describe "GET /countries/:id" do
    it "shows the country's allowances and each role's structure with its pay at the default basic" do
      create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
      structure = create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_200_000,
                                         variable_pay_percent_bp: 1_000, overtime_percent_bp: 15_000)
      create(:pay_structure_allowance, pay_structure: structure, name: "Special", percent_bp: 1_500)

      get country_path(india)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("HRA", "40.00%", "Software Engineer", "₹12,00,000", "Special 15%",
                                       "₹18,60,000", "₹20,46,000", "10.00%", "150.00%")
    end

    it "lists the roles that still need a structure" do
      create(:pay_structure, organization:, country: india, job_role: engineer)

      get country_path(india)

      expect(response.body).to include("No pay structure yet", "Accountant")
    end

    it "returns 404 for a country the organization doesn't operate in" do
      get country_path(create(:country, name: "Japan", currency_code: "JPY"))
      expect(response).to have_http_status(:not_found)
    end
  end

  it "requires setup to be complete" do
    organization.update!(setup_completed_at: nil)
    get countries_path
    expect(response).to redirect_to(onboarding_root_path)
  end
end
