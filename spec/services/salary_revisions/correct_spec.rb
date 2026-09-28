require "rails_helper"

RSpec.describe SalaryRevisions::Correct do
  let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000) }
  let(:user) { create(:user, organization: employee.organization) }
  let!(:wrong) do
    create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_500_000, reason: "promotion")
  end

  def correct(revision = wrong, void_reason: "Typed 15 instead of 12", **attributes)
    described_class.new(revision, by: user, void_reason:, attributes:)
  end

  it "voids the wrong revision and records the replacement in one go" do
    correction = correct(basic_pay: "12,00,000", effective_on: "2025-04-01", reason: "promotion", notes: "Fixed")

    expect(correction.call).to eq(:saved)
    expect(wrong.reload).to have_attributes(voided_by: user, void_reason: "Typed 15 instead of 12")
    expect(correction.replacement).to have_attributes(basic_pay: 1_200_000, effective_on: Date.new(2025, 4, 1),
                                                      reason: "promotion", notes: "Fixed", created_by: user)
    expect(employee.basic_pay_on(Date.new(2026, 1, 1))).to eq(1_200_000)
  end

  it "defaults the replacement to the original's date, amount and reason" do
    correction = described_class.new(wrong, by: user, void_reason: "x", attributes: {})

    expect(correction.replacement).to have_attributes(effective_on: Date.new(2025, 4, 1), basic_pay: 1_500_000,
                                                      reason: "promotion")
  end

  it "can move the revision to another date" do
    expect(correct(effective_on: "2025-05-01", basic_pay: "15,00,000", reason: "promotion").call).to eq(:saved)
    expect(employee.basic_pay_on(Date.new(2025, 4, 15))).to eq(1_000_000)
  end

  it "is atomic: an invalid replacement leaves the original in force" do
    correction = correct(basic_pay: "0", effective_on: "2025-04-01", reason: "promotion")

    expect(correction.call).to eq(:invalid)
    expect(correction.replacement.errors[:basic_pay]).to be_present
    expect(wrong.reload).not_to be_voided
  end

  it "needs a reason for the correction" do
    correction = correct(void_reason: "", basic_pay: "12,00,000", effective_on: "2025-04-01", reason: "promotion")

    expect(correction.call).to eq(:invalid)
    expect(correction.errors[:void_reason]).to include("can't be blank")
    expect(wrong.reload).not_to be_voided
  end

  it "reports a conflict when the original was already voided" do
    SalaryRevisions::Void.new(SalaryRevision.find(wrong.id), by: user, reason: "Duplicate").call

    expect(correct(basic_pay: "12,00,000", effective_on: "2025-04-01", reason: "promotion").call).to eq(:conflict)
    expect(employee.salary_revisions.in_force.count).to eq(1)   # only the hire revision
  end

  describe "the hire revision" do
    let(:hire) { employee.salary_revisions.find_by!(reason: "hire") }

    it "keeps the hire date and reason, and changes the amount" do
      correction = correct(hire, void_reason: "Offer letter says 9,50,000",
                                 basic_pay: "9,50,000", effective_on: "2024-06-01", reason: "appraisal")

      expect(correction.call).to eq(:saved)
      expect(correction.replacement).to have_attributes(reason: "hire", effective_on: Date.new(2024, 4, 1), basic_pay: 950_000)
      expect(hire.reload).to be_voided
    end
  end
end
