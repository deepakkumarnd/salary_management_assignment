require "rails_helper"

# Computed reports (insights) are cached under the organization's pay_data_version, so every change to data they
# depend on must bump it, whether it's made through a model, nested attributes or a bulk update.
RSpec.describe "Pay data version" do
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:structure) { create(:pay_structure, organization:, country: india) }
  let(:employee) { create(:employee, pay_structure: structure, hire_date: Date.new(2024, 4, 1)) }
  let(:user) { create(:user, organization:) }

  def version = organization.reload.pay_data_version

  def expect_bump(&change)
    before = version
    change.call
    expect(version).to be > before
  end

  {
    "an employee"             => ->(t) { t.employee },
    "a salary revision"       => ->(t) { t.create(:salary_revision, employee: t.employee) },
    "a pay structure"         => ->(t) { t.structure },
    "a role allowance"        => ->(t) { t.create(:pay_structure_allowance, pay_structure: t.structure) },
    "a country allowance"     => ->(t) { t.create(:country_allowance, organization: t.organization, country: t.india) },
    "a job role"              => ->(t) { t.create(:job_role, organization: t.organization) },
    "a department"            => ->(t) { t.create(:department, organization: t.organization) },
    "an operating country"    => ->(t) { t.organization.organization_countries.create!(country: t.create(:country)) }
  }.each do |name, build|
    it "is bumped when #{name} is created, updated or deleted" do
      record = nil
      expect_bump { record = build.call(self) }

      attribute, value = { Employee => [ :full_name, "Changed" ], SalaryRevision => [ :void_reason, "x" ],
                           PayStructure => [ :default_basic_pay, 1 ], OrganizationCountry => [ :updated_at, 1.day.from_now ] }
                         .fetch(record.class) { [ :name, "Changed #{rand(1000)}" ] }
      if record.is_a?(SalaryRevision)
        expect_bump { record.update!(voided_at: Time.current, voided_by: user, void_reason: "x") }
      elsif record.is_a?(PayStructureAllowance) || record.is_a?(CountryAllowance)
        expect_bump { record.update!(percent: "12") }
      else
        expect_bump { record.update!(attribute => value) }
      end

      expect_bump { record.destroy } unless record.is_a?(Employee) || record.is_a?(SalaryRevision)   # never deleted
    end
  end

  it "is bumped by voiding, which is a conditional bulk update" do
    revision = create(:salary_revision, employee:)
    expect_bump { SalaryRevisions::Void.new(revision, by: user, reason: "Wrong").call }
  end

  it "is bumped when role allowances change through the pay structure form (nested attributes)" do
    allowance = create(:pay_structure_allowance, pay_structure: structure)
    expect_bump { structure.update!(allowances_attributes: [ { id: allowance.id, _destroy: "1" } ]) }
  end

  it "is bumped for every organization when a country's currency changes" do
    structure
    expect_bump { india.update!(currency_code: "USD") }
  end

  it "isn't bumped by a change that is rolled back" do
    employee
    before = version
    ActiveRecord::Base.transaction do
      employee.update!(full_name: "Rolled Back")
      raise ActiveRecord::Rollback
    end
    expect(version).to eq(before)
  end

  it "isn't bumped by another organization's changes" do
    employee
    before = version
    create(:employee)
    expect(version).to eq(before)
  end
end
