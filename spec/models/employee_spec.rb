require "rails_helper"

RSpec.describe Employee, type: :model do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer, default_basic_pay: 1_200_000) }
  let(:user) { create(:user, organization:) }

  def new_employee(**attributes)
    build(:employee, pay_structure: structure, recorded_by: user, hire_date: Date.new(2024, 4, 1), **attributes)
  end

  around { |example| travel_to(Date.new(2026, 9, 28)) { example.run } }

  describe "associations" do
    subject { new_employee }

    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:country) }
    it { is_expected.to belong_to(:job_role) }
    it { is_expected.to belong_to(:department) }
    it { is_expected.to belong_to(:updated_by).class_name("User").optional }
    it { is_expected.to have_many(:salary_revisions).dependent(:restrict_with_error) }
  end

  describe "employee ID" do
    it "is assigned on create from the organization's counter, zero-padded" do
      first = create(:employee, pay_structure: structure)
      second = create(:employee, pay_structure: structure)

      expect([ first.employee_code, second.employee_code ]).to eq(%w[ACME-00001 ACME-00002])
      expect(organization.reload.next_employee_number).to eq(3)
    end

    it "is the URL parameter" do
      expect(create(:employee, pay_structure: structure).to_param).to eq("ACME-00001")
    end

    it "is never reused and uses the prefix at the time of hiring" do
      create(:employee, pay_structure: structure, email: "priya@acme.test").tap do |priya|
        priya.update!(employment_end_date: Date.new(2026, 9, 1), exit_reason: "resignation")
      end
      organization.update!(employee_code_prefix: "ACMEX")

      rehire = create(:employee, pay_structure: structure, email: "priya@acme.test")

      expect(rehire.employee_code).to eq("ACMEX-00002")
    end

    it "is read-only after create" do
      employee = create(:employee, pay_structure: structure)
      expect { employee.update!(employee_code: "ACME-99999") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(employee.reload.employee_code).to eq("ACME-00001")
    end

    it "doesn't use up a number when the employee is invalid" do
      new_employee(full_name: "").save
      expect(organization.reload.next_employee_number).to eq(1)
    end

    it "grows past five digits" do
      organization.update!(next_employee_number: 100_000)
      expect(create(:employee, pay_structure: structure).employee_code).to eq("ACME-100000")
    end
  end

  describe "hire revision" do
    it "is created with the employee from the starting basic, on the hire date" do
      employee = new_employee(initial_basic_pay: "12,00,000")
      employee.save!

      revision = employee.salary_revisions.sole
      expect(revision).to have_attributes(reason: "hire", effective_on: Date.new(2024, 4, 1), basic_pay: 1_200_000,
                                          created_by: user, organization:)
    end

    it "needs a positive starting basic" do
      employee = new_employee(initial_basic_pay: 0)
      expect(employee).not_to be_valid
      expect(employee.errors[:initial_basic_pay]).to include("must be greater than 0")
    end

    it "uses the current user as its author when none is given" do
      employee = new_employee(recorded_by: nil)
      Current.set(user:) { employee.save! }
      expect(employee.salary_revisions.sole.created_by).to eq(user)
    end
  end

  describe "country" do
    it "is read-only after create" do
      employee = create(:employee, pay_structure: structure)
      germany = create(:country, :germany)
      expect { employee.update(country: germany) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(employee.reload.country).to eq(india)
    end

    it "must be an operating country" do
      employee = new_employee(country: create(:country))
      expect(employee).not_to be_valid
      expect(employee.errors[:country]).to include("is not one of the organization's operating countries")
    end
  end

  describe "pay structure" do
    it "must exist for the country and role" do
      accountant = create(:job_role, organization:, name: "Accountant")
      employee = new_employee(job_role: accountant)

      expect(employee).not_to be_valid
      expect(employee.errors[:job_role]).to include("has no pay structure in India yet. Create one in Pay policy first.")
    end

    it "is enforced by the database (composite foreign key)" do
      employee = create(:employee, pay_structure: structure)
      accountant = create(:job_role, organization:, name: "Accountant")

      expect { employee.update_column(:job_role_id, accountant.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "can't be deleted while an employee uses it" do
      create(:employee, pay_structure: structure)
      expect(structure.destroy).to be(false)
      expect(structure.errors[:base]).to include("Cannot delete record because dependent employees exist")
    end
  end

  describe "validations" do
    subject(:employee) { new_employee }

    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:hire_date) }

    it "rejects a malformed email and normalises it" do
      employee.email = "  Priya.Nair@ACME.test "
      expect(employee.email).to eq("priya.nair@acme.test")
      employee.email = "nope"
      expect(employee).not_to be_valid
    end

    it "needs a known employment type" do
      employee.employment_type = "intern"
      expect(employee).not_to be_valid
      expect(employee.errors[:employment_type]).to include("is not included in the list")
    end

    it "refuses a hire date in the future" do
      employee.hire_date = Date.new(2026, 9, 29)
      expect(employee).not_to be_valid
      expect(employee.errors[:hire_date]).to include("can't be in the future")
    end

    it "rejects a department or role from another organization" do
      employee.department = create(:department)
      expect(employee).not_to be_valid
      expect(employee.errors[:department]).to include("must belong to the same organization")
    end
  end

  describe "email uniqueness" do
    let!(:priya) { create(:employee, pay_structure: structure, email: "priya@acme.test") }

    it "is unique among employees without an exit, ignoring case" do
      duplicate = new_employee(email: "PRIYA@acme.test")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to include("is already used by current employee ACME-00001")
    end

    it "can be reused once the other record has an exit recorded" do
      priya.update!(employment_end_date: Date.new(2026, 10, 31), exit_reason: "resignation")
      expect(new_employee(email: "priya@acme.test")).to be_valid
    end

    it "may repeat in another organization" do
      expect(build(:employee, email: "priya@acme.test", pay_structure: create(:pay_structure))).to be_valid
    end
  end

  describe "#status" do
    let(:employee) { new_employee }

    it "is active without an end date" do
      expect(employee.status).to eq(:active)
    end

    it "is leaving up to and including the last working day, and exited the day after" do
      employee.employment_end_date = Date.new(2026, 9, 28)
      expect(employee.status).to eq(:leaving)
      expect(employee.status(Date.new(2026, 9, 29))).to eq(:exited)
    end
  end

  describe "scopes" do
    let!(:active)  { create(:employee, pay_structure: structure, hire_date: Date.new(2024, 1, 1)) }
    let!(:leaving) { create(:employee, :leaving, pay_structure: structure, hire_date: Date.new(2023, 1, 1)) }
    let!(:exited)  { create(:employee, :exited, pay_structure: structure) }
    let!(:mistake) do
      create(:employee, pay_structure: structure, hire_date: Date.new(2026, 1, 1)).tap do
        it.update!(employment_end_date: Date.new(2026, 1, 1), exit_reason: "recorded_in_error")
      end
    end

    it ".employed_on includes the last working day, not the day after" do
      expect(Employee.employed_on(Date.new(2026, 9, 28))).to contain_exactly(active, leaving)
      expect(Employee.employed_on(exited.employment_end_date)).to include(exited)
      expect(Employee.employed_on(exited.employment_end_date + 1)).not_to include(exited)
    end

    it ".employed_during includes anyone employed on any day of the range" do
      expect(Employee.employed_during(Date.new(2026, 8, 1), Date.new(2026, 8, 31))).to include(exited)
      expect(Employee.employed_during(Date.new(2020, 1, 1), Date.new(2020, 12, 31))).to be_empty
    end

    it ".countable leaves out records ended as recorded in error" do
      expect(Employee.countable).to contain_exactly(active, leaving, exited)
    end
  end

  describe "basic pay as of a date" do
    let(:employee) do
      create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000)
    end

    before do
      create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_100_000)
      create(:salary_revision, employee:, effective_on: Date.new(2027, 4, 1), basic_pay: 1_200_000)   # scheduled
      create(:salary_revision, employee:, effective_on: Date.new(2026, 4, 1), basic_pay: 9_999_999,
                               voided_at: Time.current, voided_by: user, void_reason: "Typo")
    end

    it "is the latest revision in force on or before the date" do
      expect(employee.basic_pay_on(Date.new(2024, 4, 1))).to eq(1_000_000)
      expect(employee.basic_pay_on(Date.new(2026, 9, 28))).to eq(1_100_000)
      expect(employee.basic_pay_on(Date.new(2027, 4, 1))).to eq(1_200_000)
    end

    it "is available as a column through .with_basic_pay_as_of" do
      row = Employee.with_basic_pay_as_of(Date.new(2026, 9, 28)).find(employee.id)
      expect(row.basic_pay).to eq(1_100_000)
    end

    it "is nil before the hire date" do
      expect(employee.basic_pay_on(Date.new(2024, 3, 31))).to be_nil
    end
  end

  describe "changing the hire date" do
    let(:employee) do
      create(:employee, pay_structure: structure, recorded_by: user, hire_date: Date.new(2024, 4, 1),
                        initial_basic_pay: 1_000_000)
    end

    it "corrects the hire revision in the same save" do
      Current.set(user:) { employee.update!(hire_date: Date.new(2024, 3, 1)) }

      hires = employee.salary_revisions.where(reason: "hire").order(:id)
      expect(hires.map { [ it.effective_on, it.basic_pay, it.voided_at.present? ] })
        .to eq([ [ Date.new(2024, 4, 1), 1_000_000, true ], [ Date.new(2024, 3, 1), 1_000_000, false ] ])
      expect(hires.first.void_reason).to eq("Hire date changed from 1 Apr 2024 to 1 Mar 2024")
    end

    it "can't move after another revision in force" do
      create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1))

      employee.hire_date = Date.new(2025, 5, 1)

      expect(employee).not_to be_valid
      expect(employee.errors[:hire_date]).to include("must be before the salary revision on 1 Apr 2025")
    end
  end

  describe "an exited employee" do
    let(:employee) { create(:employee, :exited, pay_structure: structure) }

    it "is read-only" do
      employee.full_name = "Someone Else"
      expect(employee).not_to be_valid
      expect(employee.errors[:base]).to include("Exited employees can't be changed. Undo the exit first.")
    end

    it "can still have the exit undone" do
      employee.assign_attributes(employment_end_date: nil, exit_reason: nil, exit_notes: nil)
      expect(employee).to be_valid
    end
  end

  it "uses optimistic locking and records who changed it" do
    employee = create(:employee, pay_structure: structure)
    stale = Employee.find(employee.id)
    Current.set(user:) { employee.update!(full_name: "Priya Nair") }

    expect(employee.updated_by).to eq(user)
    expect { stale.update!(full_name: "P. Nair") }.to raise_error(ActiveRecord::StaleObjectError)
  end
end
