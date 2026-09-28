require "rails_helper"

RSpec.describe Employment::UndoEnd do
  let(:employee) { create(:employee, :exited, email: "priya@acme.test") }
  let(:user) { create(:user, organization: employee.organization) }

  it "clears the exit, even for an exited employee" do
    undo = described_class.new(employee, by: user, lock_version: employee.lock_version)

    expect(undo.call).to eq(:saved)
    expect(employee.reload).to have_attributes(employment_end_date: nil, exit_reason: nil, exit_notes: nil, status: :active)
  end

  it "is refused when a current employee now uses the same email" do
    rehire = create(:employee, pay_structure: employee.pay_structure, email: "priya@acme.test")
    undo = described_class.new(employee, by: user, lock_version: employee.lock_version)

    expect(undo.call).to eq(:invalid)
    expect(undo.employee.errors.full_messages)
      .to include("Email is already used by current employee #{rehire.employee_code}")
    expect(employee.reload.employment_end_date).to be_present
  end

  it "reports a conflict on a stale version" do
    Employee.find(employee.id).update_columns(lock_version: employee.lock_version + 1)

    expect(described_class.new(employee, by: user, lock_version: employee.lock_version).call).to eq(:conflict)
  end

  it "does nothing useful without an exit" do
    active = create(:employee)
    undo = described_class.new(active, by: user, lock_version: active.lock_version)

    expect(undo.call).to eq(:invalid)
    expect(undo.employee.errors[:base]).to include("There is no exit to undo.")
  end
end
