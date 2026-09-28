require "rails_helper"

RSpec.describe "Pay structures", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let!(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let!(:accountant) { create(:job_role, organization:, name: "Accountant") }

  let(:valid_params) do
    { pay_structure: { country_id: india.id, job_role_id: engineer.id, default_basic_pay: "12,00,000",
                       variable_pay_percent: "10", overtime_percent: "150",
                       allowances_attributes: { "0" => { name: "Special", percent: "15" } } } }
  end

  before do
    organization.countries << india
    sign_in user
  end

  describe "new" do
    it "offers only roles without a structure in the country" do
      create(:pay_structure, organization:, country: india, job_role: accountant)

      get new_pay_structure_path(country_id: india.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(">Software Engineer</option>")
      expect(response.body).not_to include(">Accountant</option>")
    end

    it "shows the country allowances that will apply" do
      create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
      get new_pay_structure_path(country_id: india.id)
      expect(response.body).to include("HRA", "40.00%")
    end
  end

  describe "create" do
    it "creates the structure with its role allowances" do
      post pay_structures_path, params: valid_params

      structure = PayStructure.where(organization:).sole
      expect(response).to redirect_to(country_path(india))
      expect(structure).to have_attributes(country: india, job_role: engineer, default_basic_pay: 1_200_000,
                                           variable_pay_percent_bp: 1_000, overtime_percent_bp: 15_000, updated_by: user)
      expect(structure.allowances.pluck(:name, :percent_bp)).to eq([ [ "Special", 1_500 ] ])
    end

    it "re-renders with errors" do
      post pay_structures_path, params: { pay_structure: valid_params[:pay_structure].merge(default_basic_pay: "0") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Default basic pay must be greater than 0")
      expect(organization.pay_structures.reload).to be_empty
    end

    it "adds a role-allowance row without saving when JavaScript is off" do
      post pay_structures_path, params: valid_params.merge(add_allowance: "1")

      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/name="pay_structure\[allowances_attributes\]\[\d+\]\[name\]"/).size).to eq(2)
      expect(organization.pay_structures.reload).to be_empty
    end

    it "refuses another organization's job role" do
      post pay_structures_path, params: { pay_structure: valid_params[:pay_structure].merge(job_role_id: create(:job_role).id) }

      expect(response).to have_http_status(:unprocessable_content)
      expect(PayStructure.count).to eq(0)
    end
  end

  describe "editing" do
    let!(:structure) do
      create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_000_000)
    end
    let!(:special) { create(:pay_structure_allowance, pay_structure: structure, name: "Special", percent_bp: 1_500) }

    it "updates the structure and its allowances" do
      patch pay_structure_path(structure), params: { pay_structure: {
        default_basic_pay: "11,00,000", lock_version: structure.lock_version,
        allowances_attributes: { "0" => { id: special.id, name: "Special", percent: "20" },
                                 "1" => { name: "Meal", percent: "2" } }
      } }

      expect(response).to redirect_to(country_path(india))
      expect(structure.reload.default_basic_pay).to eq(1_100_000)
      expect(structure.allowances.order(:name).pluck(:name, :percent_bp)).to eq([ [ "Meal", 200 ], [ "Special", 2_000 ] ])
    end

    it "doesn't change the country or role" do
      patch pay_structure_path(structure), params: { pay_structure: {
        job_role_id: accountant.id, country_id: create(:country).id, lock_version: structure.lock_version
      } }

      expect(structure.reload).to have_attributes(job_role: engineer, country: india)
    end

    it "rejects a stale version with 409 and shows who changed it" do
      colleague = create(:user, organization:, full_name: "Priya Nair")
      Current.set(user: colleague) { PayStructure.find(structure.id).update!(default_basic_pay: 1_050_000) }

      patch pay_structure_path(structure), params: { pay_structure: { default_basic_pay: "9,00,000", lock_version: 0 } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("Priya Nair changed this pay structure", "Saved value: ₹10,50,000")
      expect(structure.reload.default_basic_pay).to eq(1_050_000)
    end

    it "deletes the structure" do
      delete pay_structure_path(structure)

      expect(response).to redirect_to(country_path(india))
      expect(PayStructure.exists?(structure.id)).to be(false)
    end
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create(:pay_structure, country: india) }
    let(:foreign_requests) do
      [
        [ :get, edit_pay_structure_path(foreign) ],
        [ :patch, pay_structure_path(foreign), { pay_structure: { default_basic_pay: "1" } } ],
        [ :delete, pay_structure_path(foreign) ],
        [ :get, new_pay_structure_path(country_id: create(:country).id) ]                   # not an operating country
      ]
    end
  end
end
