require "rails_helper"

RSpec.describe Employment::End do
  let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1)) }
  let(:user) { create(:user, organization: employee.organization) }

  around { |example| travel_to(Date.new(2026, 9, 28)) { example.run } }

  def end_employment(**attributes)
    described_class.new(employee, by: user, attributes: { employment_end_date: "2026-10-31", exit_reason: "resignation",
                                                          exit_notes: "Moving abroad",
                                                          lock_version: employee.lock_version }.merge(attributes))
  end

  it "records the last working day, reason and notes" do
    expect(end_employment.call).to eq(:saved)
    expect(employee.reload).to have_attributes(employment_end_date: Date.new(2026, 10, 31), exit_reason: "resignation",
                                               exit_notes: "Moving abroad", updated_by: user)
    expect(employee.status).to eq(:leaving)
  end

  it "allows a date in the past" do
    expect(end_employment(employment_end_date: "2026-08-31").call).to eq(:saved)
    expect(employee.reload.status).to eq(:exited)
  end

  it "needs a date and a known reason" do
    ending = end_employment(employment_end_date: "", exit_reason: "")

    expect(ending.call).to eq(:invalid)
    expect(ending.employee.errors[:employment_end_date]).to include("can't be blank")
    expect(ending.employee.errors[:exit_reason]).to include("can't be blank")
  end

  it "refuses a last working day before the hire date" do
    ending = end_employment(employment_end_date: "2024-03-31")

    expect(ending.call).to eq(:invalid)
    expect(ending.employee.errors[:employment_end_date]).to include("can't be before the hire date (1 Apr 2024)")
  end

  it "is refused while revisions in force take effect after the last working day, and lists them" do
    scheduled = create(:salary_revision, employee:, effective_on: Date.new(2027, 4, 1))
    create(:salary_revision, employee:, effective_on: Date.new(2027, 5, 1), voided_at: Time.current,
                             voided_by: user, void_reason: "Cancelled")

    ending = end_employment

    expect(ending.call).to eq(:invalid)
    expect(ending.blocking_revisions).to eq([ scheduled ])
    expect(ending.employee.errors[:employment_end_date])
      .to include("is before a salary revision that takes effect on 1 Apr 2027: void it first")
    expect(employee.reload.employment_end_date).to be_nil
  end

  it "reports a conflict when someone else changed the employee" do
    Employee.find(employee.id).update!(full_name: "Changed Elsewhere")

    ending = end_employment(lock_version: 0)

    expect(ending.call).to eq(:conflict)
    expect(ending.latest.full_name).to eq("Changed Elsewhere")
    expect(employee.reload.employment_end_date).to be_nil
  end

  it "refuses when an exit is already recorded" do
    end_employment.call
    ending = described_class.new(employee.reload, by: user, attributes: { employment_end_date: "2026-11-30",
                                                                          exit_reason: "resignation",
                                                                          lock_version: employee.lock_version })

    expect(ending.call).to eq(:invalid)
    expect(ending.employee.errors[:base]).to include("An exit is already recorded. Undo it first to change it.")
  end
end
