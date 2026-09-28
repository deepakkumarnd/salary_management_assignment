require "rails_helper"

RSpec.describe "Country allowances", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }

  before do
    organization.countries << india
    sign_in user
  end

  describe "creating" do
    it "adds an allowance to the country" do
      get new_country_allowance_path(india)
      expect(response).to have_http_status(:ok)

      post country_allowances_path(india), params: { country_allowance: { name: "HRA", percent: "40" } }

      expect(response).to redirect_to(country_path(india))
      expect(CountryAllowance.where(organization:).sole).to have_attributes(name: "HRA", percent_bp: 4_000, country: india,
                                                                      updated_by: user)
    end

    it "re-renders with errors" do
      post country_allowances_path(india), params: { country_allowance: { name: "", percent: "300" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Name can&#39;t be blank", "Percent must be between 0.01 and 200")
    end

    it "refuses the name of a role allowance in this country" do
      structure = create(:pay_structure, organization:, country: india,
                                         job_role: create(:job_role, organization:, name: "Software Engineer"))
      create(:pay_structure_allowance, pay_structure: structure, name: "Special")

      post country_allowances_path(india), params: { country_allowance: { name: "special", percent: "10" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Special is already a role allowance for Software Engineer in India")
    end
  end

  describe "editing" do
    let!(:allowance) { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

    it "updates the allowance" do
      patch country_allowance_path(india, allowance),
            params: { country_allowance: { name: "HRA", percent: "45", lock_version: allowance.lock_version } }

      expect(response).to redirect_to(country_path(india))
      expect(allowance.reload.percent_bp).to eq(4_500)
    end

    it "rejects a stale version with 409, says who changed it, and lets the user re-apply" do
      colleague = create(:user, organization:, full_name: "Priya Nair")
      Current.set(user: colleague) { CountryAllowance.find(allowance.id).update!(percent: "45") }

      patch country_allowance_path(india, allowance),
            params: { country_allowance: { name: "HRA", percent: "50", lock_version: 0 } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("Priya Nair changed this allowance", "Saved value: 45.00")
      expect(response.body).to match(/value="50"/)                       # the user's own edit is kept
      expect(response.body).to match(/value="1"[^>]*name="country_allowance\[lock_version\]"/)
      expect(allowance.reload.percent_bp).to eq(4_500)

      patch country_allowance_path(india, allowance),
            params: { country_allowance: { name: "HRA", percent: "50", lock_version: 1 } }
      expect(allowance.reload.percent_bp).to eq(5_000)
    end

    it "deletes the allowance" do
      delete country_allowance_path(india, allowance)

      expect(response).to redirect_to(country_path(india))
      expect(CountryAllowance.exists?(allowance.id)).to be(false)
    end
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create(:country_allowance, country: india) }
    let(:japan) { create(:country, name: "Japan", currency_code: "JPY") }
    let(:foreign_requests) do
      [
        [ :get, edit_country_allowance_path(india, foreign) ],
        [ :patch, country_allowance_path(india, foreign), { country_allowance: { percent: "1" } } ],
        [ :delete, country_allowance_path(india, foreign) ],
        [ :get, new_country_allowance_path(japan) ],                                        # not an operating country
        [ :post, country_allowances_path(japan), { country_allowance: { name: "X", percent: "1" } } ]
      ]
    end
  end
end
