require "rails_helper"

RSpec.describe SalaryRevision, type: :model do
  let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1), initial_basic_pay: 1_000_000) }
  let(:user) { create(:user, organization: employee.organization) }

  describe "associations" do
    subject { build(:salary_revision, employee:) }

    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:employee) }
    it { is_expected.to belong_to(:created_by).class_name("User") }
    it { is_expected.to belong_to(:voided_by).class_name("User").optional }
  end

  describe "validations" do
    it "needs a positive whole basic, accepting separators" do
      revision = build(:salary_revision, employee:, basic_pay: "11,00,000")
      expect(revision.basic_pay).to eq(1_100_000)

      revision.basic_pay = 0
      expect(revision).not_to be_valid
    end

    it "needs a known reason" do
      expect(build(:salary_revision, employee:, reason: "bonus")).not_to be_valid
    end

    it "must be effective on or after the hire date" do
      revision = build(:salary_revision, employee:, effective_on: Date.new(2024, 3, 31))
      expect(revision).not_to be_valid
      expect(revision.errors[:effective_on]).to include("can't be before the hire date (1 Apr 2024)")
    end

    it "must not be effective after the last working day" do
      employee.update!(employment_end_date: Date.new(2026, 9, 30), exit_reason: "resignation")
      revision = build(:salary_revision, employee:, effective_on: Date.new(2026, 10, 1))

      expect(revision).not_to be_valid
      expect(revision.errors[:effective_on]).to include("can't be after the last working day (30 Sep 2026)")
    end

    it "puts a hire revision on the hire date" do
      revision = build(:salary_revision, employee:, reason: "hire", effective_on: Date.new(2024, 5, 1))
      expect(revision).not_to be_valid
      expect(revision.errors[:effective_on]).to include("must be the hire date for a hire revision")
    end

    it "rejects an employee from another organization" do
      revision = build(:salary_revision, employee:, organization: create(:organization))
      expect(revision).not_to be_valid
      expect(revision.errors[:employee]).to include("must belong to the same organization")
    end
  end

  describe "database rules" do
    it "allows one revision in force per employee and day" do
      create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1))
      duplicate = build(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1))

      expect { duplicate.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the day again once the first is voided" do
      first = create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1))
      first.update!(voided_at: Time.current, voided_by: user, void_reason: "Wrong amount")

      expect(create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1))).to be_persisted
    end
  end

  describe "append-only" do
    let!(:revision) { create(:salary_revision, employee:, effective_on: Date.new(2025, 4, 1), basic_pay: 1_100_000) }

    it "refuses changes to anything but the void fields" do
      expect { revision.update!(basic_pay: 1) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(revision.reload.basic_pay).to eq(1_100_000)
    end

    it "allows voiding" do
      revision.update!(voided_at: Time.current, voided_by: user, void_reason: "Wrong amount")
      expect(revision.reload).to be_voided
    end

    it "can't be deleted" do
      expect { revision.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(SalaryRevision.exists?(revision.id)).to be(true)
    end
  end

  describe "flags" do
    around { |example| travel_to(Time.utc(2026, 9, 28, 12)) { example.run } }

    it "is scheduled when effective after today" do
      expect(build(:salary_revision, employee:, effective_on: Date.new(2026, 9, 29))).to be_scheduled
      expect(build(:salary_revision, employee:, effective_on: Date.new(2026, 9, 28))).not_to be_scheduled
    end

    it "is backdated when entered after the month it took effect in" do
      expect(create(:salary_revision, employee:, effective_on: Date.new(2026, 4, 1))).to be_backdated
      expect(create(:salary_revision, employee:, effective_on: Date.new(2026, 9, 1))).not_to be_backdated
    end
  end
end
