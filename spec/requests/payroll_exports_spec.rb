require "rails_helper"

RSpec.describe "Payroll exports", type: :request do
  let(:organization) { create(:organization, name: "Acme Corp") }
  let(:user) { create(:user, organization:, full_name: "Deepak Kumar") }
  let(:india) { create(:country, :india) }
  let(:structure) { create(:pay_structure, organization:, country: india) }
  let!(:employee) do
    create(:employee, pay_structure: structure, full_name: "Priya Nair", hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_200_000)
  end

  before { sign_in user }

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  it "offers countries and months, defaulting to the current month, and shows the export log" do
    create(:payroll_export, organization:, country: india, period_start: Date.new(2026, 8, 1), exported_by: user, row_count: 42)

    get payroll_exports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("India", "October 2026", "April 2024")   # hire month .. next month
    expect(response.body).to match(/selected="selected" value="2026-09"/)
    expect(response.body).to include("August 2026", "42", "Deepak Kumar")
  end

  it "shows the summary before download" do
    create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), amount: 5_000, description: "Advance", created_by: user)

    get new_payroll_export_path(country_id: india.id, month: "2026-09")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("September 2026", "₹1,00,000", "₹95,000", "Download CSV",
                                     "Nothing has been exported for India yet", "past months use today's policy percentages")
  end

  it "downloads the CSV and logs the export" do
    post payroll_exports_path, params: { country_id: india.id, month: "2026-09" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment", "acme-corp-payroll-india-2026-09.csv")
    expect(response.body.b).to start_with("\xEF\xBB\xBFemployee_id".b)

    log = organization.payroll_exports.sole
    expect(log).to have_attributes(country: india, period_start: Date.new(2026, 9, 1), row_count: 1, exported_by: user,
                                   sha256: Digest::SHA256.hexdigest(response.body))
  end

  it "rejects a month outside the hire month .. next month range" do
    get new_payroll_export_path(country_id: india.id, month: "2027-01")
    expect(response).to redirect_to(payroll_exports_path)

    post payroll_exports_path, params: { country_id: india.id, month: "bogus" }
    expect(response).to redirect_to(payroll_exports_path)
    expect(PayrollExport.count).to eq(0)
  end

  it "never includes another organization's employees" do
    create_foreign_employee(country: india, full_name: "Someone Elsewhere")

    post payroll_exports_path, params: { country_id: india.id, month: "2026-09" }

    expect(response.body).not_to include("Someone Elsewhere")
  end

  it_behaves_like "tenant isolated" do
    let(:japan) { create(:country, name: "Japan", currency_code: "JPY") }
    let(:foreign_requests) do
      [
        [ :get, new_payroll_export_path(country_id: japan.id, month: "2026-09") ],
        [ :post, payroll_exports_path, { country_id: japan.id, month: "2026-09" } ]
      ]
    end
  end
end
