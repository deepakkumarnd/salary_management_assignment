require "rails_helper"

RSpec.describe "Employees", type: :request do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:engineering) { create(:department, organization:, name: "Engineering") }
  let!(:structure) do
    create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_200_000)
  end

  before do
    create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000)
    sign_in user
  end

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  def employee_params(**overrides)
    { employee: { full_name: "Priya Nair", email: "Priya@Acme.test", country_id: india.id, job_role_id: engineer.id,
                  department_id: engineering.id, employment_type: "full_time", hire_date: "2026-09-01",
                  initial_basic_pay: "12,00,000" }.merge(overrides) }
  end

  describe "GET /employees" do
    it "lists employees with status, basic and gross as of today" do
      create(:employee, pay_structure: structure, department: engineering, full_name: "Priya Nair",
                        hire_date: Date.new(2025, 1, 1), initial_basic_pay: 1_000_000)

      get employees_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ACME-00001", "Priya Nair", "India", "Engineering", "Software Engineer", "Active",
                                       "₹10,00,000", "₹14,00,000")
    end

    it "is the home page after sign-in" do
      get authenticated_root_path
      expect(response.body).to include("Add employee")
    end
  end

  describe "creating" do
    it "creates the employee with the next ID and their hire revision" do
      get new_employee_path
      expect(response).to have_http_status(:ok)

      post employees_path, params: employee_params

      employee = Employee.find_by!(organization:, employee_code: "ACME-00001")
      expect(response).to redirect_to(employee_path(employee))
      expect(employee).to have_attributes(full_name: "Priya Nair", email: "priya@acme.test", country: india)
      expect(employee.salary_revisions.sole).to have_attributes(reason: "hire", basic_pay: 1_200_000, created_by: user)
    end

    it "re-renders with errors" do
      post employees_path, params: employee_params(full_name: "", initial_basic_pay: "abc", hire_date: "2026-10-01")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Full name can&#39;t be blank", "can&#39;t be in the future")
      expect(Employee.count).to eq(0)
      expect(organization.reload.next_employee_number).to eq(1)
    end

    it "explains when the role has no pay structure in the country" do
      post employees_path, params: employee_params(job_role_id: create(:job_role, organization:, name: "Accountant").id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("has no pay structure in India yet")
    end

    it "refuses another organization's department" do
      post employees_path, params: employee_params(department_id: create(:department).id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Employee.count).to eq(0)
    end
  end

  describe "the employee page" do
    let!(:employee) do
      create(:employee, pay_structure: structure, department: engineering, full_name: "Priya Nair",
                        hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000, recorded_by: user)
    end

    it "is at /employees/<employee ID> and shows today's pay, the history and the scheduled raise" do
      create(:salary_revision, employee:, effective_on: Date.new(2027, 4, 1), basic_pay: 1_100_000, reason: "appraisal")

      get "/employees/ACME-00001"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Priya Nair", "ACME-00001", "₹10,00,000", "HRA", "₹14,00,000",
                                       "Rises to", "₹11,00,000", "1 Apr 2027", "Scheduled", "+₹1,00,000 (+10.0%)")
    end

    it "has no delete route" do
      delete "/employees/ACME-00001"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing" do
    let!(:employee) do
      create(:employee, pay_structure: structure, department: engineering, full_name: "Priya Nair",
                        hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000)
    end

    it "updates the employee but not the country" do
      patch employee_path(employee), params: { employee: { full_name: "Priya N.", country_id: create(:country).id,
                                                           lock_version: employee.lock_version } }

      expect(response).to redirect_to(employee_path(employee))
      expect(employee.reload).to have_attributes(full_name: "Priya N.", country: india, updated_by: user)
    end

    it "moves the hire revision when the hire date changes" do
      patch employee_path(employee), params: { employee: { hire_date: "2024-03-01", lock_version: employee.lock_version } }

      expect(employee.basic_pay_on(Date.new(2024, 3, 1))).to eq(1_000_000)
      expect(employee.salary_revisions.in_force.sole.effective_on).to eq(Date.new(2024, 3, 1))
    end

    it "rejects a stale version with 409, says who changed it, and keeps the user's edit" do
      colleague = create(:user, organization:, full_name: "Deepak Kumar")
      Current.set(user: colleague) { Employee.find(employee.id).update!(full_name: "Priya Nair-Menon") }

      patch employee_path(employee), params: { employee: { full_name: "P. Nair", lock_version: 0 } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("Deepak Kumar changed this employee", "Saved value: Priya Nair-Menon", 'value="P. Nair"')
      expect(employee.reload.full_name).to eq("Priya Nair-Menon")
    end

    it "is refused for an exited employee" do
      employee.update!(employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation")

      get edit_employee_path(employee)
      expect(response).to redirect_to(employee_path(employee))

      patch employee_path(employee), params: { employee: { full_name: "X", lock_version: employee.lock_version } }
      expect(employee.reload.full_name).to eq("Priya Nair")
    end
  end

  describe "pay preview" do
    it "renders the breakdown for a country, role and basic" do
      get preview_pay_structures_path, params: { country_id: india.id, job_role_id: engineer.id, basic_pay: "12,00,000" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('turbo-frame id="pay_preview"', "₹12,00,000", "HRA", "₹4,80,000", "₹16,80,000")
    end

    it "says when the role has no pay structure in the country" do
      accountant = create(:job_role, organization:, name: "Accountant")
      get preview_pay_structures_path, params: { country_id: india.id, job_role_id: accountant.id, basic_pay: "100" }

      expect(response.body).to include("There is no pay structure for Accountant in India yet")
    end

    it "compares a revision with the basic in force on its date and flags backdating" do
      employee = create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000)

      get preview_pay_structures_path, params: { employee_id: employee.employee_code, basic_pay: "11,00,000",
                                                 effective_on: "2026-04-01" }

      expect(response.body).to include("Basic in force on 1 Apr 2026", "₹10,00,000", "+₹1,00,000 (+10.0%)", "Backdated")
    end

    it "doesn't use another organization's pay structures" do
      foreign = create(:pay_structure, country: india, default_basic_pay: 100)

      get preview_pay_structures_path, params: { country_id: india.id, job_role_id: foreign.job_role_id, basic_pay: "100" }

      expect(response.body).not_to include("Gross pay")
    end
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create_foreign_employee(country: india) }
    let(:foreign_requests) do
      [
        [ :get, employee_path(foreign) ],
        [ :get, edit_employee_path(foreign) ],
        [ :patch, employee_path(foreign), { employee: { full_name: "X" } } ],
        [ :get, preview_pay_structures_path(employee_id: foreign.employee_code, basic_pay: "1") ]
      ]
    end
  end

  it "never lists another organization's employees" do
    foreign = create_foreign_employee(country: india, full_name: "Someone Elsewhere")
    get employees_path
    expect(response.body).not_to include(foreign.full_name)
  end
end
