require "rails_helper"

RSpec.describe Demo::Populate do
  let(:today) { Date.new(2026, 9, 28) }
  let(:organization) { create(:organization, :pending_setup, name: "ACME", employee_code_prefix: "ACME") }
  let!(:hr) { create(:user, organization:, email: "hr@acme.test") }

  before do
    { "Australia" => "AUD", "Canada" => "CAD", "Germany" => "EUR", "India" => "INR", "Japan" => "JPY",
      "Singapore" => "SGD", "United Kingdom" => "GBP", "United States" => "USD" }.each do |name, currency_code|
      Country.find_or_create_by!(name:) { it.currency_code = currency_code }
    end
  end

  around { |example| travel_to(Time.utc(2026, 9, 28, 10)) { example.run } }

  def populate(count = 300, org = organization) = described_class.new(org, employees: count).call

  describe "an organization whose setup is pending" do
    before { populate }

    it "applies standard defaults and completes setup" do
      organization.reload
      expect(organization).to be_setup_completed
      expect(organization.countries.count).to eq(8)
      expect(organization.country_allowances.pluck(:name, :percent_bp)).to eq([ [ "HRA", 4_000 ] ])
      expect(organization.departments.count).to be_between(6, 10)
      expect(organization.job_roles.count).to be_between(12, 18)
    end

    it "creates a pay structure for every country and role, with more variable pay for sales" do
      expect(organization.pay_structures.count).to eq(organization.countries.count * organization.job_roles.count)
      sales = organization.pay_structures.joins(:job_role).where(job_roles: { name: "Sales Executive" })
      expect(sales.pluck(:variable_pay_percent_bp)).to all(be_between(3_000, 5_000))
      engineer_india = organization.pay_structures.joins(:job_role, :country)
                                   .find_by(job_roles: { name: "Software Engineer" }, countries: { name: "India" })
      expect(engineer_india).to have_attributes(default_basic_pay: 1_200_000, variable_pay_percent_bp: 1_000)
    end

    it "adds the requested number of employees with IDs from the organization's sequence" do
      expect(organization.employees.count).to eq(300)
      expect(organization.employees.order(:employee_code).pluck(:employee_code).values_at(0, -1)).to eq(%w[ACME-00001 ACME-00300])
      expect(organization.reload.next_employee_number).to eq(301)
    end

    it "keeps every employee valid by the model's own rules" do
      invalid = organization.employees.includes(:country, :job_role, :department, :organization).reject(&:valid?)
      expect(invalid.map { [ it.employee_code, it.errors.full_messages ] }).to eq([])
      expect(organization.employees.where("hire_date > ?", today)).to be_empty
    end

    it "spreads hire dates over six years and mixes statuses" do
      hires = organization.employees.pluck(:hire_date)
      expect(hires.min).to be <= today - 5.years
      statuses = organization.employees.map { it.status(today) }.tally
      expect(statuses[:active]).to be > 200
      expect(statuses[:exited]).to be_between(15, 60)            # about 12%
      expect(statuses.fetch(:leaving, 0)).to be_between(1, 10)   # about 1%, leaving in the next 60 days
      expect(organization.employees.where(exit_reason: "recorded_in_error").count).to be >= 1
    end

    it "gives everyone one hire revision on the hire date and a history that fits their employment" do
      revisions = organization.salary_revisions.in_force.to_a.group_by(&:employee_id)
      organization.employees.each do |employee|
        own = revisions.fetch(employee.id)
        expect(own.count(&:hire?)).to eq(1)
        expect(own.find(&:hire?).effective_on).to eq(employee.hire_date)
        expect(own.map(&:effective_on)).to all(be >= employee.hire_date)
        expect(own.map(&:effective_on)).to all(be <= employee.employment_end_date) if employee.employment_end_date
        expect(own.map(&:effective_on).uniq.size).to eq(own.size)
      end
      reasons = organization.salary_revisions.group(:reason).count
      expect(reasons.keys).to include("hire", "appraisal", "promotion", "market_adjustment")
      expect(organization.salary_revisions.count).to be > 3 * 300
    end

    it "includes scheduled raises for next April and backdated entries made this month" do
      scheduled = organization.salary_revisions.where(effective_on: Date.new(2027, 4, 1))
      backdated = organization.salary_revisions.where(created_at: today.beginning_of_month..).where(effective_on: ...today.beginning_of_month)
      expect(scheduled.count).to be >= 5
      expect(backdated.count).to be >= 1
    end

    it "adds deductions for this month and last month, only in months people were employed" do
      deductions = organization.payroll_deductions.includes(:employee).to_a
      expect(deductions.map(&:period_start).uniq).to contain_exactly(Date.new(2026, 8, 1), Date.new(2026, 9, 1))
      expect(deductions.select(&:unpaid_leave?).size).to be > 10
      expect(deductions.select(&:other?).map(&:description).uniq).to eq([ "Salary advance recovery" ])
      expect(deductions.reject(&:valid?)).to be_empty
    end

    it "logs past exports for every country" do
      exports = organization.payroll_exports
      expect(exports.where(period_start: Date.new(2026, 8, 1)).count).to eq(8)
      expect(exports.where(period_start: Date.new(2026, 9, 1))).to be_empty
      expect(exports.pluck(:exported_by_id).uniq).to eq([ hr.id ])
    end

    it "produces data the payroll and insights run on" do
      india = Country.find_by!(name: "India")
      run = Payroll::Run.new(organization, india, Payroll::Month.parse("2026-09"))

      expect(run.summary.headcount).to be > 50
      expect(run.summary.deductions).to be > 0
      expect(Insights::CountryReport.new(organization, india).summary.headcount).to be > 50
    end

    it "bumps the pay data version so cached insights recompute" do
      expect(organization.reload.pay_data_version).to be > 0
    end
  end

  it "uses what HR configured when setup is already complete" do
    organization.update!(setup_completed_at: Time.current)
    germany = Country.find_by!(name: "Germany")
    organization.countries << germany
    create(:department, organization:, name: "Research")
    create(:job_role, organization:, name: "Chemist")

    populate(20)

    expect(organization.countries).to eq([ germany ])
    expect(organization.pay_structures.sole).to have_attributes(country: germany, job_role: JobRole.find_by!(name: "Chemist"))
    expect(organization.employees.pluck(:country_id).uniq).to eq([ germany.id ])
  end

  it "adds more employees on a second run, continuing the ID sequence and keeping existing structures" do
    populate(50)
    structures = organization.pay_structures.pluck(:id, :updated_at)

    populate(50)

    expect(organization.employees.count).to eq(100)
    expect(organization.employees.maximum(:employee_code)).to eq("ACME-00100")
    expect(organization.pay_structures.pluck(:id, :updated_at)).to match_array(structures)
    expect(organization.employees.where(employment_end_date: nil).group(:email).having("COUNT(*) > 1").count).to be_empty
  end

  it "is deterministic" do
    other = create(:organization, :pending_setup, name: "Other", employee_code_prefix: "OTH")
    create(:user, organization: other)

    populate(40)
    populate(40, other)

    expect(other.employees.order(:employee_code).pluck(:full_name, :hire_date))
      .to eq(organization.employees.order(:employee_code).pluck(:full_name, :hire_date))
  end

  it "needs an HR user to author the history" do
    lonely = create(:organization, :pending_setup)
    expect { populate(10, lonely) }.to raise_error(ArgumentError, /no active HR user/)
  end
end
