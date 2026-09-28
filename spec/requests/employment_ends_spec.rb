require "rails_helper"

RSpec.describe "End of employment", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:structure) { create(:pay_structure, organization:) }
  let!(:employee) { create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), email: "priya@acme.test") }

  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  def end_params(**overrides)
    { employee: { employment_end_date: "2026-10-31", exit_reason: "resignation", exit_notes: "",
                  lock_version: employee.lock_version }.merge(overrides) }
  end

  it "records a leaver, who shows as Leaving" do
    get new_employee_employment_end_path(employee)
    expect(response).to have_http_status(:ok)

    post employee_employment_end_path(employee), params: end_params

    expect(response).to redirect_to(employee_path(employee, tab: "employment"))
    expect(flash[:notice]).to include("is leaving", "31 Oct 2026")
    follow_redirect!
    expect(response.body).to include("Leaving (until 31 Oct)")
  end

  it "refuses with 422 and lists revisions after the last working day" do
    create(:salary_revision, employee:, effective_on: Date.new(2027, 4, 1), basic_pay: 2_000_000)

    post employee_employment_end_path(employee), params: end_params

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Is before a salary revision that takes effect on 1 Apr 2027: void it first", "Void")
  end

  it "returns 409 on a stale version" do
    Employee.find(employee.id).update!(full_name: "Changed")

    post employee_employment_end_path(employee), params: end_params(lock_version: 0)

    expect(response).to have_http_status(:conflict)
    expect(employee.reload.employment_end_date).to be_nil
  end

  describe "undoing" do
    before { employee.update!(employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation") }

    it "clears the exit" do
      delete employee_employment_end_path(employee), params: { lock_version: employee.lock_version }

      expect(response).to redirect_to(employee_path(employee))
      expect(employee.reload.status).to eq(:active)
    end

    it "is refused when a current employee now uses the email" do
      create(:employee, pay_structure: structure, email: "priya@acme.test")

      delete employee_employment_end_path(employee), params: { lock_version: employee.lock_version }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("The exit can&#39;t be undone", "is already used by current employee")
      expect(employee.reload.employment_end_date).to be_present
    end

    it "returns 409 on a stale version" do
      delete employee_employment_end_path(employee), params: { lock_version: employee.lock_version - 1 }

      expect(response).to have_http_status(:conflict)
      expect(employee.reload.employment_end_date).to be_present
    end
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create_foreign_employee }
    let(:foreign_requests) do
      [
        [ :get, new_employee_employment_end_path(foreign) ],
        [ :post, employee_employment_end_path(foreign), end_params ],
        [ :delete, employee_employment_end_path(foreign), { lock_version: 0 } ]
      ]
    end
  end
end
