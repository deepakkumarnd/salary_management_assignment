require "rails_helper"

RSpec.describe EmployeeSearch do
  let(:today) { Date.new(2026, 9, 28) }
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:india) { create(:country, :india) }
  let(:germany) { create(:country, :germany) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:accountant) { create(:job_role, organization:, name: "Accountant") }
  let(:engineering) { create(:department, organization:, name: "Engineering") }
  let(:finance) { create(:department, organization:, name: "Finance") }
  let(:structures) do
    [ india, germany ].product([ engineer, accountant ]).to_h do |country, role|
      [ [ country, role ], create(:pay_structure, organization:, country:, job_role: role) ]
    end
  end

  around { |example| travel_to(today) { example.run } }

  def hire(name, email: nil, country: india, role: engineer, department: engineering, basic: 1_000_000,
           hire_date: Date.new(2024, 4, 1), end_date: nil, exit_reason: "resignation")
    create(:employee, pay_structure: structures.fetch([ country, role ]), department:, full_name: name,
                      email: email || "#{name.parameterize}@acme.test", initial_basic_pay: basic, hire_date:).tap do
      it.update!(employment_end_date: end_date, exit_reason:) if end_date
    end
  end

  def search(**params) = described_class.new(organization, params, today:).results

  let!(:priya)   { hire("Priya Nair", basic: 1_200_000) }                                             # ACME-00001
  let!(:rahul)   { hire("Rahul Verma", role: accountant, department: finance, basic: 900_000) }       # ACME-00002
  let!(:anna)    { hire("Anna Schmidt", country: germany, basic: 70_000) }                            # ACME-00003
  let!(:leaving) { hire("Lena Leaving", end_date: Date.new(2026, 10, 31)) }                           # ACME-00004
  let!(:exited)  { hire("Ed Exited", end_date: Date.new(2026, 8, 31)) }                               # ACME-00005
  let!(:mistake) { hire("Mia Mistake", end_date: Date.new(2024, 4, 1), exit_reason: "recorded_in_error") }   # ACME-00006

  describe "default" do
    it "returns current employees (Active + Leaving), by employee ID" do
      expect(search).to eq([ priya, rahul, anna, leaving ])
    end

    it "ignores blank parameters" do
      expect(search(q: " ", country_id: "", department_id: "", job_role_id: "", status: "", sort: "", dir: ""))
        .to eq([ priya, rahul, anna, leaving ])
    end
  end

  describe "search box" do
    it "matches part of the name, ignoring case" do
      expect(search(q: "priya")).to eq([ priya ])
      expect(search(q: "NAIR")).to eq([ priya ])
    end

    it "matches part of the email" do
      expect(search(q: "rahul-verma@")).to eq([ rahul ])
      expect(search(q: "@acme.test").size).to eq(4)
    end

    it "matches part of the employee ID" do
      expect(search(q: "acme-00003")).to eq([ anna ])
      expect(search(q: "00002")).to eq([ rahul ])
    end

    it "trims surrounding whitespace" do
      expect(search(q: "  priya  ")).to eq([ priya ])
    end

    it "treats % and _ literally" do
      expect(search(q: "%")).to be_empty
      expect(search(q: "_")).to be_empty
      odd = hire("Odd_Name 100%")
      expect(search(q: "_Name 100%")).to eq([ odd ])
    end
  end

  describe "filters" do
    it "filters by country" do
      expect(search(country_id: germany.id)).to eq([ anna ])
    end

    it "filters by department" do
      expect(search(department_id: finance.id)).to eq([ rahul ])
    end

    it "filters by job role" do
      expect(search(job_role_id: accountant.id)).to eq([ rahul ])
    end

    it "combines filters and search (all must match)" do
      expect(search(country_id: india.id, job_role_id: engineer.id, department_id: engineering.id))
        .to eq([ priya, leaving ])
      expect(search(country_id: india.id, job_role_id: engineer.id, q: "lena")).to eq([ leaving ])
      expect(search(country_id: germany.id, q: "priya")).to be_empty
    end

    it "matches nothing for ids of another organization" do
      other_department = create(:department)
      expect(search(department_id: other_department.id)).to be_empty
    end
  end

  describe "status" do
    it "filters active (no end date)" do
      expect(search(status: "active")).to eq([ priya, rahul, anna ])
    end

    it "filters leaving (last working day today or later)" do
      expect(search(status: "leaving")).to eq([ leaving ])
    end

    it "filters exited, leaving out records ended as recorded in error" do
      expect(search(status: "exited")).to eq([ exited ])
    end

    it "shows everyone with all, including recorded in error" do
      expect(search(status: "all")).to eq([ priya, rahul, anna, leaving, exited, mistake ])
    end

    it "treats someone on their last working day as leaving, and exited the day after" do
      last_day = described_class.new(organization, { status: "leaving" }, today: Date.new(2026, 10, 31)).results
      day_after = described_class.new(organization, { status: "exited" }, today: Date.new(2026, 11, 1)).results

      expect(last_day).to eq([ leaving ])
      expect(day_after).to include(leaving)
    end

    it "falls back to current for an unknown value" do
      expect(search(status: "bogus")).to eq([ priya, rahul, anna, leaving ])
    end
  end

  describe "basic pay column" do
    it "is the basic in force today: backdated revisions count, scheduled ones don't yet" do
      create(:salary_revision, employee: priya, effective_on: Date.new(2026, 4, 1), basic_pay: 1_300_000)   # backdated
      create(:salary_revision, employee: rahul, effective_on: Date.new(2027, 4, 1), basic_pay: 1_000_000)   # scheduled

      rows = search.index_by(&:id)

      expect(rows[priya.id].basic_pay).to eq(1_300_000)
      expect(rows[rahul.id].basic_pay).to eq(900_000)
    end
  end

  describe "sorting" do
    it "sorts by name, either way" do
      expect(search(sort: "full_name").map(&:full_name)).to eq([ "Anna Schmidt", "Lena Leaving", "Priya Nair", "Rahul Verma" ])
      expect(search(sort: "full_name", dir: "desc").first).to eq(rahul)
    end

    it "sorts by basic pay" do
      expect(search(sort: "basic_pay", dir: "desc").first(2)).to eq([ priya, leaving ])
      expect(search(sort: "basic_pay").first).to eq(anna)
    end

    it "sorts by country, department and job role names" do
      expect(search(sort: "country").first).to eq(anna)                   # Germany before India
      expect(search(sort: "department", dir: "desc").first).to eq(rahul)  # Finance after Engineering
      expect(search(sort: "job_role").first).to eq(rahul)                 # Accountant first
    end

    it "sorts by hire date and last working day" do
      newest = hire("New Hire", hire_date: Date.new(2026, 9, 1))
      expect(search(sort: "hire_date", dir: "desc").first).to eq(newest)
      expect(search(sort: "employment_end_date", dir: "desc").first).to eq(leaving)
    end

    it "breaks ties by employee ID so pages are stable" do
      expect(search(sort: "country", dir: "asc").map(&:employee_code)).to eq(%w[ACME-00003 ACME-00001 ACME-00002 ACME-00004])
    end

    it "falls back to employee ID for an unknown column, and ascending for an unknown direction" do
      expect(search(sort: "gross; DROP TABLE employees", dir: "sideways")).to eq([ priya, rahul, anna, leaving ])
    end
  end

  it "never returns another organization's employees" do
    other = create(:employee, full_name: "Priya Elsewhere")

    expect(described_class.new(other.organization, { q: "priya" }, today:).results).to eq([ other ])
    expect(search(q: "priya", status: "all")).to eq([ priya ])
  end

  describe "#active_filters" do
    it "describes the chosen filters for badges and the empty state" do
      filters = described_class.new(organization, { q: "priya", country_id: india.id.to_s, job_role_id: engineer.id.to_s,
                                                    status: "exited" }, today:).active_filters

      expect(filters.map { it.values_at(:key, :label) })
        .to eq([ [ :q, "“priya”" ], [ :country_id, "India" ], [ :job_role_id, "Software Engineer" ], [ :status, "Exited" ] ])
    end
  end
end
