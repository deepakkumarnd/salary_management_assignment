require "rails_helper"

RSpec.describe SalaryRevisions::Void do
  let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000) }
  let(:user) { create(:user, organization: employee.organization, full_name: "Deepak Kumar") }
  let(:colleague) { create(:user, organization: employee.organization, full_name: "Priya Nair") }
  let!(:raise_revision) { create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_100_000) }

  it "voids the revision with who, when and why" do
    freeze_time do
      voiding = described_class.new(raise_revision, by: user, reason: "Wrong amount")

      expect(voiding.call).to eq(:saved)
      expect(raise_revision.reload).to have_attributes(voided_at: Time.current, voided_by: user, void_reason: "Wrong amount")
      expect(employee.basic_pay_on(Date.new(2026, 1, 1))).to eq(1_000_000)
    end
  end

  it "needs a reason" do
    voiding = described_class.new(raise_revision, by: user, reason: " ")

    expect(voiding.call).to eq(:invalid)
    expect(voiding.revision.errors[:void_reason]).to include("can't be blank")
    expect(raise_revision.reload).not_to be_voided
  end

  it "reports a conflict with who voided it when someone already did" do
    described_class.new(SalaryRevision.find(raise_revision.id), by: colleague, reason: "Duplicate").call
    voiding = described_class.new(raise_revision, by: user, reason: "Wrong amount")

    expect(voiding.call).to eq(:conflict)
    expect(voiding.revision).to have_attributes(voided_by: colleague, void_reason: "Duplicate")
  end

  it "won't void the hire revision on its own" do
    voiding = described_class.new(employee.salary_revisions.find_by!(reason: "hire"), by: user, reason: "Wrong")

    expect(voiding.call).to eq(:invalid)
    expect(voiding.revision.errors[:base]).to include("The hire revision can't be voided on its own. Correct it instead.")
  end

  it "refuses an exited employee's revisions" do
    employee.update!(employment_end_date: 1.month.ago.to_date, exit_reason: "resignation")

    expect(described_class.new(raise_revision, by: user, reason: "Wrong").call).to eq(:invalid)
  end
end
