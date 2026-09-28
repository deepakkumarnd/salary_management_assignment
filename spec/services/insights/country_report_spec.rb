require "rails_helper"

RSpec.describe Insights::CountryReport do
  let(:today) { Date.new(2026, 9, 28) }
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:accountant) { create(:job_role, organization:, name: "Accountant") }
  let(:engineering) { create(:department, organization:, name: "Engineering") }
  let(:finance) { create(:department, organization:, name: "Finance") }
  let(:engineer_india) do
    create(:pay_structure, organization:, country: india, job_role: engineer, variable_pay_percent_bp: 1_000).tap do
      create(:pay_structure_allowance, pay_structure: it, name: "Special", percent_bp: 1_000)
    end
  end
  let(:accountant_india) { create(:pay_structure, organization:, country: india, job_role: accountant, variable_pay_percent_bp: 0) }

  around { |example| travel_to(today) { example.run } }

  before { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  def hire(structure, basic, department: engineering, **attributes)
    create(:employee, pay_structure: structure, department:, initial_basic_pay: basic, hire_date: Date.new(2024, 4, 1), **attributes)
  end

  def report = described_class.new(organization, india, today:)

  it "summarises current employees' basic, gross and total target pay" do
    hire(engineer_india, 1_000_000)   # gross 1,500,000 (HRA 40% + Special 10%), total 1,650,000
    hire(engineer_india, 2_000_000)   # gross 3,000,000, total 3,300,000
    hire(accountant_india, 600_000, department: finance)   # gross 840,000 (HRA only), total 840,000

    summary = report.summary

    expect(summary.headcount).to eq(3)
    expect(summary.basic).to have_attributes(min: 600_000, max: 2_000_000, median: 1_000_000, average: 1_200_000)
    expect(summary.gross).to have_attributes(min: 840_000, max: 3_000_000, median: 1_500_000, average: 1_780_000)
    expect(summary.total_target).to have_attributes(min: 840_000, max: 3_300_000, median: 1_650_000, average: 1_930_000)
    expect(summary.cost_to_company).to eq(5_790_000)   # total target pay: 1,650,000 + 3,300,000 + 840,000
    expect(summary.gross.total).to eq(5_340_000)
  end

  it "uses the basic in force today: backdated revisions count, scheduled ones don't" do
    employee = hire(accountant_india, 600_000)
    create(:salary_revision, employee:, effective_on: Date.new(2026, 4, 1), basic_pay: 700_000)
    create(:salary_revision, employee:, effective_on: Date.new(2027, 4, 1), basic_pay: 900_000)

    expect(report.summary.basic.max).to eq(700_000)
  end

  it "counts Active and Leaving, and leaves out exited people and records created in error" do
    hire(accountant_india, 600_000)
    hire(accountant_india, 700_000, employment_end_date: Date.new(2026, 10, 31), exit_reason: "resignation")   # leaving
    hire(accountant_india, 800_000, employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation")    # exited
    hire(accountant_india, 900_000, employment_end_date: Date.new(2024, 4, 1), exit_reason: "recorded_in_error")

    expect(report.summary.headcount).to eq(2)
    expect(report.summary.basic.max).to eq(700_000)
  end

  it "only covers its own country and organization" do
    hire(accountant_india, 600_000)
    hire(create(:pay_structure, organization:, country: germany, job_role: engineer), 60_000)
    create(:employee, pay_structure: create(:pay_structure, country: india), hire_date: Date.new(2024, 4, 1))   # another org

    expect(report.summary.headcount).to eq(1)
  end

  it "breaks the figures down by job role and by department, largest group first" do
    hire(engineer_india, 1_000_000)
    hire(engineer_india, 2_000_000, department: finance)
    hire(accountant_india, 600_000, department: finance)

    expect(report.by_job_role.map { [ it.name, it.headcount, it.basic.median ] })
      .to eq([ [ "Software Engineer", 2, 1_500_000 ], [ "Accountant", 1, 600_000 ] ])
    expect(report.by_department.map { [ it.name, it.headcount, it.gross.max ] })
      .to eq([ [ "Finance", 2, 3_000_000 ], [ "Engineering", 1, 1_500_000 ] ])
    expect(report.by_department.map(&:cost_to_company)).to eq([ 3_300_000 + 840_000, 1_650_000 ])
  end

  it "reflects a change to an allowance percentage immediately" do
    hire(accountant_india, 1_000_000)
    CountryAllowance.find_by!(name: "HRA").update!(percent: "50")

    expect(report.summary.gross.max).to eq(1_500_000)
  end

  it "is empty when nobody is employed in the country" do
    expect(report.summary.headcount).to eq(0)
    expect(report.summary.basic).to be_empty
    expect(report.by_job_role).to be_empty
  end

  it "runs a fixed number of queries whatever the headcount" do
    3.times { hire(engineer_india, 1_000_000) }
    queries = count_queries { described_class.new(organization, india, today:).summary }
    5.times { hire(accountant_india, 600_000, department: finance) }

    expect(count_queries { described_class.new(organization, india, today:).summary }).to be <= queries + 1
  end

  describe "caching" do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }
    let(:user) { create(:user, organization:) }
    let!(:employee) { hire(accountant_india, 1_000_000) }

    def cached_report(on: today) = described_class.new(organization, india, today: on, cache:)

    def employee_queries(&block)
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].include?(%(FROM "employees")) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end

    it "computes once and serves later reports from the cache" do
      expect(cached_report.summary.gross.max).to eq(1_400_000)
      expect(employee_queries { cached_report.summary; cached_report.by_job_role; cached_report.by_department }).to eq(0)
    end

    {
      "a country allowance changes"   => ->(t) { CountryAllowance.find_by!(name: "HRA").update!(percent: "50") },
      "a role allowance is added"     => ->(t) { t.create(:pay_structure_allowance, pay_structure: t.accountant_india, name: "Meal", percent_bp: 1_000) },
      "a salary revision is recorded" => ->(t) { t.create(:salary_revision, employee: t.employee, effective_on: Date.new(2026, 4, 1), basic_pay: 2_000_000) },
      "an employee leaves"            => ->(t) { t.employee.update!(employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation") },
      "someone is hired"              => ->(t) { t.hire(t.accountant_india, 5_000_000) }
    }.each do |change, apply|
      it "recomputes when #{change}" do
        before = cached_report.summary
        apply.call(self)
        after = cached_report.summary

        expect([ after.headcount, after.gross.max ]).not_to eq([ before.headcount, before.gross.max ])
        expect(after).to eq(described_class.new(organization, india, today:, cache: ActiveSupport::Cache::NullStore.new).summary)
      end
    end

    it "recomputes when a revision is voided (a bulk update)" do
      revision = create(:salary_revision, employee:, effective_on: Date.new(2026, 4, 1), basic_pay: 2_000_000)
      expect(cached_report.summary.basic.max).to eq(2_000_000)

      SalaryRevisions::Void.new(revision, by: user, reason: "Wrong").call

      expect(cached_report.summary.basic.max).to eq(1_000_000)
    end

    it "recomputes on a new day, when statuses and scheduled revisions may have changed" do
      create(:salary_revision, employee:, effective_on: Date.new(2026, 9, 29), basic_pay: 1_100_000)
      expect(cached_report.summary.basic.max).to eq(1_000_000)
      expect(cached_report(on: Date.new(2026, 9, 29)).summary.basic.max).to eq(1_100_000)
    end

    it "keeps organizations and countries apart" do
      cached_report.summary
      germany_report = described_class.new(organization, germany, today:, cache:)
      expect(germany_report.summary.headcount).to eq(0)
    end
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
