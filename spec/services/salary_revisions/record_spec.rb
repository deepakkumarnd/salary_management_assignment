require "rails_helper"

RSpec.describe SalaryRevisions::Record do
  let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000) }
  let(:user) { create(:user, organization: employee.organization) }

  around { |example| travel_to(Time.utc(2026, 9, 20, 10)) { example.run } }

  def record(**attributes)
    described_class.new(employee, by: user,
                                  attributes: { effective_on: "2026-10-01", basic_pay: "11,00,000", reason: "appraisal",
                                                notes: "Annual review" }.merge(attributes))
  end

  it "records a revision, authored by the user" do
    recording = record

    expect(recording.call).to eq(:saved)
    expect(recording.revision).to have_attributes(effective_on: Date.new(2026, 10, 1), basic_pay: 1_100_000,
                                                  reason: "appraisal", notes: "Annual review", created_by: user,
                                                  organization: employee.organization)
    expect(recording.revision).to be_scheduled
  end

  it "flags a backdated entry (effective before the current month)" do
    recording = record(effective_on: "2026-04-01")

    expect(recording.call).to eq(:saved)
    expect(recording.revision).to be_backdated
  end

  it "refuses the hire reason" do
    recording = record(reason: "hire")

    expect(recording.call).to eq(:invalid)
    expect(recording.revision.errors[:reason]).to include("can't be hire: the hire revision is created with the employee")
  end

  it "refuses a date before the hire date" do
    recording = record(effective_on: "2024-03-01")

    expect(recording.call).to eq(:invalid)
    expect(recording.revision.errors[:effective_on]).to include("can't be before the hire date (1 Apr 2024)")
  end

  it "refuses a date after the last working day" do
    employee.update!(employment_end_date: Date.new(2026, 9, 30), exit_reason: "resignation")

    expect(record(effective_on: "2026-10-01").call).to eq(:invalid)
  end

  it "refuses an exited employee" do
    employee.update!(employment_end_date: Date.new(2026, 8, 31), exit_reason: "resignation")
    recording = record(effective_on: "2026-06-01")

    expect(recording.call).to eq(:invalid)
    expect(recording.revision.errors[:base]).to include("#{employee.full_name} has left, so their pay can't be changed")
  end

  it "refuses a second revision in force on the same date" do
    record.call
    recording = record(basic_pay: "12,00,000")

    expect(recording.call).to eq(:invalid)
    expect(recording.revision.errors[:effective_on])
      .to include("a revision already exists for 1 Oct 2026: void or correct it instead")
  end

  it "turns a race on the unique index into the same field error" do
    record.call
    recording = record(basic_pay: "12,00,000")
    allow(recording.revision).to receive(:valid?).and_return(true)   # the other writer won between check and insert

    expect(recording.call).to eq(:invalid)
    expect(recording.revision.errors[:effective_on])
      .to include("a revision already exists for 1 Oct 2026: void or correct it instead")
  end
end
