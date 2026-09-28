require "rails_helper"

RSpec.describe "Payroll deductions", type: :request do
  let(:organization) { create(:organization) }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:structure) { create(:pay_structure, organization:, country: india) }
  let!(:employee) { create(:employee, pay_structure: structure, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1)) }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  describe "the month page" do
    it "lists the country's roster for the month with days employed" do
      create(:employee, pay_structure: structure, full_name: "Left In August", hire_date: Date.new(2024, 4, 1),
                        employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation")

      get month_deductions_path("2026-09", country_id: india.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("September 2026", "Priya Nair", employee.employee_code)
      expect(response.body).not_to include("Left In August")
    end

    it "pages through the roster, 50 at a time, keeping the country, search and month, with totals for everyone" do
      stub_const("PayrollDeductionsController::PER_PAGE", 2)
      others = Array.new(3) { |i| create(:employee, pay_structure: structure, full_name: "Person #{i + 1}", hire_date: Date.new(2024, 4, 1)) }
      create(:payroll_deduction, employee: others.last, period_start: Date.new(2026, 9, 1), amount: 5_000, created_by: user)

      get month_deductions_path("2026-09", country_id: india.id)

      expect(response.body).to include("1–2 of 4", employee.full_name, "Person 1", "₹5,000</strong> other deductions")   # totals: whole roster
      expect(response.body).not_to include("Person 3")
      expect(response.body).to include("/deductions/2026-09?country_id=#{india.id}&amp;page=2")

      get month_deductions_path("2026-09", country_id: india.id, page: 2)

      expect(response.body).to include("3–4 of 4", "Person 3")
      expect(response.body).not_to include("Person 1<")
    end

    it "keeps the search when paging" do
      stub_const("PayrollDeductionsController::PER_PAGE", 1)
      create(:employee, pay_structure: structure, full_name: "Priya Two", hire_date: Date.new(2024, 4, 1))

      get month_deductions_path("2026-09", country_id: india.id, q: "priya")

      expect(response.body).to include("1–1 of 2", "q=priya")
    end

    it "searches the roster by name or employee ID" do
      create(:employee, pay_structure: structure, full_name: "Anna Schmidt", hire_date: Date.new(2024, 4, 1))

      get month_deductions_path("2026-09", country_id: india.id, q: "priya")

      expect(response.body).to include("Priya Nair")
      expect(response.body).not_to include("Anna Schmidt")
    end

    it "defaults to the current month and the first operating country" do
      get deductions_path
      expect(response).to redirect_to(month_deductions_path("2026-09", country_id: india.id))
    end

    it "rejects a malformed month" do
      get "/deductions/2026-13", params: { country_id: india.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "entering deductions" do
    it "records unpaid leave and answers with the updated row" do
      post payroll_deductions_path, headers: stream, params: { payroll_deduction: {
        employee_id: employee.employee_code, month: "2026-09", kind: "unpaid_leave", unpaid_days: "1.5"
      } }

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="deductions_#{employee.id}_2026-09"), 'value="1.5"')
      expect(employee.payroll_deductions.sole).to have_attributes(unpaid_half_days: 3, created_by: user,
                                                                  period_start: Date.new(2026, 9, 1))
    end

    it "records another deduction" do
      post payroll_deductions_path, headers: stream, params: { payroll_deduction: {
        employee_id: employee.employee_code, month: "2026-09", kind: "other", amount: "5,000", description: "Salary advance recovery"
      } }

      expect(employee.payroll_deductions.sole).to have_attributes(amount: 5_000, description: "Salary advance recovery")
    end

    it "accepts last month and next month" do
      %w[2026-08 2026-10].each do |month|
        post payroll_deductions_path, headers: stream, params: { payroll_deduction: {
          employee_id: employee.employee_code, month:, kind: "other", amount: "100", description: "Adjustment"
        } }
        expect(response).to have_http_status(:ok)
      end
      expect(employee.payroll_deductions.map(&:period_start)).to contain_exactly(Date.new(2026, 8, 1), Date.new(2026, 10, 1))
    end

    it "refuses an older month" do
      post payroll_deductions_path, headers: stream, params: { payroll_deduction: {
        employee_id: employee.employee_code, month: "2026-07", kind: "other", amount: "100", description: "Late"
      } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can only be changed for August 2026, September 2026 or October 2026")
      expect(PayrollDeduction.count).to eq(0)
    end

    describe "a closed month" do
      let!(:advance) do
        create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), amount: 5_000, description: "Advance",
                                   created_by: user).tap { it.update_column(:period_start, Date.new(2026, 7, 1)) }
      end

      it "is shown read-only" do
        get month_deductions_path("2026-07", country_id: india.id)

        expect(response.body).to include("Advance", "₹5,000", "closed")
        expect(response.body).not_to include("Add deduction", "Save unpaid days", "Save Advance", "Delete Advance")
      end

      it "refuses edits and deletions" do
        patch payroll_deduction_path(advance), headers: stream,
                                               params: { payroll_deduction: { amount: "1", lock_version: advance.lock_version } }
        expect(response).to have_http_status(:unprocessable_content)

        delete payroll_deduction_path(advance), headers: stream
        expect(response).to have_http_status(:unprocessable_content)

        expect(advance.reload.amount).to eq(5_000)
      end
    end

    it "shows errors in the row with 422" do
      post payroll_deductions_path, headers: stream, params: { payroll_deduction: {
        employee_id: employee.employee_code, month: "2026-09", kind: "unpaid_leave", unpaid_days: "40"
      } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be more than the 30 days employed in September 2026")
    end

    it "updates, and clears unpaid leave when the days are emptied" do
      leave = create(:payroll_deduction, :unpaid_leave, employee:, period_start: Date.new(2026, 9, 1), created_by: user)

      patch payroll_deduction_path(leave), headers: stream,
                                           params: { payroll_deduction: { unpaid_days: "2.5", lock_version: leave.lock_version } }
      expect(leave.reload).to have_attributes(unpaid_half_days: 5, updated_by: user)

      patch payroll_deduction_path(leave), headers: stream,
                                           params: { payroll_deduction: { unpaid_days: "", lock_version: leave.lock_version } }
      expect(PayrollDeduction.exists?(leave.id)).to be(false)
    end

    it "rejects a stale version with 409 and says who changed it" do
      other = create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), amount: 5_000, created_by: user)
      colleague = create(:user, organization:, full_name: "Anita Rao")
      Current.set(user: colleague) { PayrollDeduction.find(other.id).update!(amount: 6_000) }

      patch payroll_deduction_path(other), headers: stream,
                                           params: { payroll_deduction: { amount: "7000", description: "Advance", lock_version: 0 } }

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("Anita Rao changed this deduction")
      expect(other.reload.amount).to eq(6_000)
    end

    it "deletes a deduction" do
      other = create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), created_by: user)

      delete payroll_deduction_path(other), headers: stream

      expect(PayrollDeduction.exists?(other.id)).to be(false)
    end

    it "redirects back to the month page without Turbo" do
      post payroll_deductions_path, params: { payroll_deduction: {
        employee_id: employee.employee_code, month: "2026-09", kind: "other", amount: "100", description: "Canteen"
      } }
      expect(response).to redirect_to(month_deductions_path("2026-09", country_id: india.id))
    end
  end

  it "shows deductions on the employee page" do
    create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), amount: 5_000, description: "Advance", created_by: user)

    get employee_path(employee, tab: "deductions")

    expect(response.body).to include("Deductions", "September 2026", "Advance")
  end

  it_behaves_like "tenant isolated" do
    let(:foreign) { create_foreign_employee(country: india) }
    let(:foreign_deduction) { create(:payroll_deduction, employee: foreign, period_start: Date.new(2026, 9, 1)) }
    let(:foreign_requests) do
      [
        [ :post, payroll_deductions_path, { payroll_deduction: { employee_id: foreign.employee_code, month: "2026-09",
                                                                 kind: "other", amount: "1", description: "x" } } ],
        [ :patch, payroll_deduction_path(foreign_deduction), { payroll_deduction: { amount: "1" } } ],
        [ :delete, payroll_deduction_path(foreign_deduction) ],
        [ :get, month_deductions_path("2026-09", country_id: create(:country, name: "Japan", currency_code: "JPY").id) ]
      ]
    end
  end
end
