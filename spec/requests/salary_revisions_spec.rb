require "rails_helper"

RSpec.describe "Salary revisions", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:structure) { create(:pay_structure, organization:, country: india) }
  let!(:employee) do
    create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000)
  end

  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 9, 20, 10)) { example.run } }

  describe "recording" do
    it "pre-fills today and the current basic" do
      get new_employee_salary_revision_path(employee)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="2026-09-20"', 'value="10,00,000"')
    end

    it "records the revision and says when it is backdated" do
      post employee_salary_revisions_path(employee),
           params: { salary_revision: { effective_on: "2026-04-01", basic_pay: "11,00,000", reason: "appraisal" } }

      expect(response).to redirect_to(employee_path(employee, tab: "history"))
      expect(flash[:notice]).to include("backdated to 1 Apr 2026", "arrears")
      expect(employee.basic_pay_on(Date.new(2026, 5, 1))).to eq(1_100_000)
    end

    it "refuses a second revision for the same date with 422" do
      create(:salary_revision, employee:, effective_on: Date.new(2026, 4, 1))

      post employee_salary_revisions_path(employee),
           params: { salary_revision: { effective_on: "2026-04-01", basic_pay: "12,00,000", reason: "appraisal" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("A revision already exists for 1 Apr 2026: void or correct it instead")
    end

    it "is refused for an exited employee" do
      employee.update!(employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation")

      post employee_salary_revisions_path(employee),
           params: { salary_revision: { effective_on: "2026-06-01", basic_pay: "12,00,000", reason: "appraisal" } }

      expect(response).to redirect_to(employee_path(employee))
      expect(employee.salary_revisions.count).to eq(1)
    end
  end

  describe "voiding" do
    let!(:revision) { create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_100_000) }

    it "voids with a reason" do
      get new_employee_salary_revision_void_path(employee, revision)
      expect(response).to have_http_status(:ok)

      post employee_salary_revision_void_path(employee, revision), params: { salary_revision: { void_reason: "Entered twice" } }

      expect(response).to redirect_to(employee_path(employee, tab: "history"))
      expect(revision.reload).to have_attributes(voided_by: user, void_reason: "Entered twice")
    end

    it "needs a reason" do
      post employee_salary_revision_void_path(employee, revision), params: { salary_revision: { void_reason: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 409 with who voided it when it was already voided" do
      colleague = create(:user, organization:, full_name: "Priya Nair")
      SalaryRevisions::Void.new(SalaryRevision.find(revision.id), by: colleague, reason: "Duplicate").call

      post employee_salary_revision_void_path(employee, revision), params: { salary_revision: { void_reason: "Wrong" } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("Priya Nair already voided this revision", "Duplicate")
    end
  end

  describe "correcting" do
    let!(:revision) { create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_500_000) }

    it "voids the wrong revision and records the right one" do
      get new_employee_salary_revision_correction_path(employee, revision)
      expect(response.body).to include('value="15,00,000"')

      post employee_salary_revision_correction_path(employee, revision),
           params: { correction: { effective_on: "2025-04-01", basic_pay: "11,00,000", reason: "appraisal", void_reason: "Typo" } }

      expect(response).to redirect_to(employee_path(employee, tab: "history"))
      expect(revision.reload).to be_voided
      expect(employee.basic_pay_on(Date.new(2026, 1, 1))).to eq(1_100_000)
    end

    it "keeps the original when the correction is invalid" do
      post employee_salary_revision_correction_path(employee, revision),
           params: { correction: { effective_on: "2025-04-01", basic_pay: "0", reason: "appraisal", void_reason: "Typo" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(revision.reload).not_to be_voided
    end
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create_foreign_employee(country: india) }
    let(:foreign_revision) { create(:salary_revision, employee: foreign) }
    let(:revision) { create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1)) }
    let(:foreign_requests) do
      [
        [ :get, new_employee_salary_revision_path(foreign) ],
        [ :post, employee_salary_revisions_path(foreign), { salary_revision: { effective_on: "2026-01-01", basic_pay: "1", reason: "appraisal" } } ],
        [ :post, employee_salary_revision_void_path(foreign, foreign_revision), { salary_revision: { void_reason: "x" } } ],
        [ :post, employee_salary_revision_correction_path(foreign, foreign_revision), { correction: { void_reason: "x" } } ],
        # another organization's revision reached through one of our own employees
        [ :post, employee_salary_revision_void_path(employee, foreign_revision), { salary_revision: { void_reason: "x" } } ]
      ]
    end
  end
end
