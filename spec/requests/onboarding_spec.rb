require "rails_helper"

RSpec.describe "Onboarding", type: :request do
  let(:organization) { create(:organization, :pending_setup, name: "Acme Corp") }
  let(:user) { create(:user, organization:) }
  let!(:india) { create(:country, :india) }
  let!(:germany) { create(:country, :germany) }

  before { sign_in user }

  def complete_setup_data
    organization.countries << india
    create(:department, organization:)
    create(:job_role, organization:)
  end

  describe "the setup gate" do
    it "sends every app page to the wizard until setup is complete" do
      get authenticated_root_path
      expect(response).to redirect_to(onboarding_root_path)
    end

    it "resumes at the current step" do
      get onboarding_root_path
      expect(response).to redirect_to(edit_onboarding_organization_path)

      organization.countries << india
      get onboarding_root_path
      expect(response).to redirect_to(edit_onboarding_allowances_path)
    end

    it "shows the finish page when everything required is in place" do
      complete_setup_data

      get onboarding_root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setup")
    end

    it "closes the wizard once setup is complete" do
      organization.update!(setup_completed_at: Time.current)

      [ onboarding_root_path, edit_onboarding_organization_path, edit_onboarding_countries_path ].each do |path|
        get path
        expect(response).to redirect_to(authenticated_root_path)
      end
    end
  end

  describe "step 1: organization" do
    it "shows the form with the suggested prefix" do
      get edit_onboarding_organization_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme Corp", "ACME")
    end

    it "saves and continues to countries" do
      patch onboarding_organization_path,
            params: { organization: { name: "Globex", employee_code_prefix: "gbx", standard_hours_per_week: "37" } }

      expect(response).to redirect_to(edit_onboarding_countries_path)
      expect(organization.reload).to have_attributes(name: "Globex", employee_code_prefix: "GBX",
                                                     standard_hours_per_week: 37)
    end

    it "re-renders with errors" do
      patch onboarding_organization_path,
            params: { organization: { name: "", employee_code_prefix: "A1", standard_hours_per_week: "90" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be blank", "must be 2 to 6 letters, A to Z")
      expect(organization.reload.name).to eq("Acme Corp")
    end

    it "does not let the user complete setup through this form" do
      patch onboarding_organization_path,
            params: { organization: { name: "Globex", setup_completed_at: Time.current } }
      expect(organization.reload.setup_completed_at).to be_nil
    end
  end

  describe "step 2: countries" do
    it "lists the supported countries" do
      get edit_onboarding_countries_path
      expect(response.body).to include("India", "Germany", "INR")
    end

    it "saves the chosen countries and continues to allowances" do
      patch onboarding_countries_path, params: { organization: { country_ids: [ "", india.id, germany.id ] } }

      expect(response).to redirect_to(edit_onboarding_allowances_path)
      expect(organization.countries).to contain_exactly(india, germany)
    end

    it "requires at least one country" do
      patch onboarding_countries_path, params: { organization: { country_ids: [ "" ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose at least one country")
    end
  end

  describe "step 3: country allowances" do
    it "needs countries first" do
      get edit_onboarding_allowances_path
      expect(response).to redirect_to(edit_onboarding_countries_path)
    end

    context "with operating countries" do
      before { organization.countries << india << germany }

      it "shows a section per operating country" do
        get edit_onboarding_allowances_path
        expect(response.body).to include("India", "Germany")
      end

      it "saves allowances and continues to departments & job roles" do
        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {
          "0" => { country_id: india.id, name: "HRA", percent: "40" },
          "1" => { country_id: germany.id, name: "", percent: "" }
        } } }

        expect(response).to redirect_to(edit_onboarding_catalogue_path)
        expect(organization.country_allowances.pluck(:name, :percent_bp)).to eq([ [ "HRA", 4_000 ] ])
      end

      it "edits and removes existing allowances" do
        hra = create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
        lta = create(:country_allowance, organization:, country: india, name: "LTA", percent_bp: 500)

        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {
          "0" => { id: hra.id, name: "HRA", percent: "45" },
          "1" => { id: lta.id, _destroy: "1" }
        } } }

        expect(hra.reload.percent_bp).to eq(4_500)
        expect(CountryAllowance.exists?(lta.id)).to be(false)
      end

      it "starts each country with one empty row, or none once it has allowances" do
        create(:country_allowance, organization:, country: india, name: "HRA")

        get edit_onboarding_allowances_path

        expect(response.body.scan(/name="organization\[country_allowances_attributes\]\[\d+\]\[name\]"/).size)
          .to eq(2)   # HRA + Germany's empty row (the <template> row uses NEW_RECORD, not a number)
      end

      it "adds an empty row without saving when JavaScript is off" do
        patch onboarding_allowances_path, params: { add_allowance: india.id, organization: { country_allowances_attributes: {
          "0" => { country_id: india.id, name: "HRA", percent: "40" }
        } } }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('value="HRA"')
        expect(response.body.scan(/name="organization\[country_allowances_attributes\]\[\d+\]\[name\]"/).size)
          .to eq(3)   # India: HRA + the added row; Germany: one empty row
        expect(organization.country_allowances.reload).to be_empty
      end

      it "is optional" do
        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {} } }
        expect(response).to redirect_to(edit_onboarding_catalogue_path)
      end

      it "re-renders with errors" do
        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {
          "0" => { country_id: india.id, name: "HRA", percent: "250" }
        } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("must be between 0.01 and 200")
        expect(organization.country_allowances.reload).to be_empty
      end

      it "refuses a country the organization doesn't operate in" do
        japan = create(:country, name: "Japan", currency_code: "JPY")

        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {
          "0" => { country_id: japan.id, name: "Housing", percent: "10" }
        } } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("is not one of the organization&#39;s operating countries")
        expect(organization.country_allowances.reload).to be_empty
      end

      it "can't change another organization's allowance" do
        foreign = create(:country_allowance, country: india, percent_bp: 4_000)

        patch onboarding_allowances_path, params: { organization: { country_allowances_attributes: {
          "0" => { id: foreign.id, percent: "1" }
        } } }

        expect(response).to have_http_status(:not_found)
        expect(foreign.reload.percent_bp).to eq(4_000)
      end
    end
  end

  describe "step 4: departments & job roles" do
    it "pre-fills suggestions" do
      get edit_onboarding_catalogue_path
      expect(response.body).to include("Engineering", "Software Engineer")
    end

    it "saves the lists and shows the finish page" do
      organization.countries << india

      patch onboarding_catalogue_path,
            params: { onboarding_catalogue_form: { departments: "Engineering\nSales", job_roles: "Accountant" } }

      expect(response).to redirect_to(onboarding_root_path)
      expect(organization.departments.pluck(:name)).to contain_exactly("Engineering", "Sales")
      expect(organization.job_roles.pluck(:name)).to eq([ "Accountant" ])
    end

    it "re-renders with errors" do
      patch onboarding_catalogue_path, params: { onboarding_catalogue_form: { departments: "", job_roles: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Add at least one department")
    end
  end

  describe "finishing" do
    it "completes setup and opens the app" do
      complete_setup_data

      post onboarding_completion_path

      expect(response).to redirect_to(authenticated_root_path)
      expect(organization.reload).to be_setup_completed
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "sends the user to the first missing step" do
      post onboarding_completion_path

      expect(response).to redirect_to(edit_onboarding_countries_path)
      expect(organization.reload).not_to be_setup_completed
    end
  end

  describe "tenant isolation" do
    it "only changes the signed-in user's organization" do
      other = create(:organization, :pending_setup, name: "Other Co", employee_code_prefix: "OTH")

      patch onboarding_organization_path, params: { organization: { name: "Globex", employee_code_prefix: "GBX" } }
      patch onboarding_countries_path, params: { organization: { country_ids: [ india.id ] } }

      expect(other.reload).to have_attributes(name: "Other Co", employee_code_prefix: "OTH")
      expect(other.countries).to be_empty
    end

    it "never shows another organization's allowances" do
      organization.countries << india
      create(:country_allowance, country: india, name: "Secret Allowance")

      get edit_onboarding_allowances_path

      expect(response.body).not_to include("Secret Allowance")
    end
  end
end
