require "rails_helper"

RSpec.describe PayrollDeduction, type: :model do
  let(:employee) { create(:employee, hire_date: Date.new(2026, 9, 16)) }
  let(:september) { Date.new(2026, 9, 1) }

  def unpaid(days, **attributes) = build(:payroll_deduction, :unpaid_leave, employee:, period_start: september, unpaid_days: days, **attributes)

  around { |example| travel_to(Date.new(2026, 9, 28)) { example.run } }

  describe "unpaid leave" do
    it "takes days in half-day steps and stores half days" do
      expect(unpaid("1.5").unpaid_half_days).to eq(3)
      expect(unpaid("2").tap(&:save!).reload.unpaid_days).to eq("2.0")   # typed values are shown back as typed
    end

    it "refuses anything but positive half days" do
      [ "0", "-1", "1.25", "abc", "" ].each do |days|
        deduction = unpaid(days)
        expect(deduction).not_to be_valid, "expected #{days.inspect} to be invalid"
        expect(deduction.errors[:unpaid_days]).to be_present
      end
    end

    it "can't exceed the days employed that month" do
      expect(unpaid("15")).to be_valid          # employed 16–30 Sep: 15 days
      deduction = unpaid("15.5")
      expect(deduction).not_to be_valid
      expect(deduction.errors[:unpaid_days]).to include("can't be more than the 15 days employed in September 2026")
    end

    it "is one entry per employee and month" do
      unpaid("1").save!
      duplicate = unpaid("2")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:base]).to include("Unpaid leave is already recorded for September 2026: change that entry instead")
    end
  end

  describe "other deductions" do
    it "needs a positive whole amount and a description, and allows several a month" do
      create(:payroll_deduction, employee:, period_start: september, amount: "5,000", description: "Advance recovery")
      expect(build(:payroll_deduction, employee:, period_start: september, amount: 100, description: "Canteen")).to be_valid

      deduction = build(:payroll_deduction, employee:, period_start: september, amount: "0", description: "")
      expect(deduction).not_to be_valid
      expect(deduction.errors[:amount]).to be_present
      expect(deduction.errors[:description]).to include("can't be blank")
    end
  end

  it "only fits a month the employee was employed in" do
    deduction = build(:payroll_deduction, employee:, period_start: Date.new(2026, 8, 1))
    expect(deduction).not_to be_valid
    expect(deduction.errors[:period_start]).to include("must be a month in which the employee was employed")
  end

  describe "month" do
    let(:employee) { create(:employee, hire_date: Date.new(2024, 4, 1)) }

    let(:message) { "can only be changed for August 2026, September 2026 or October 2026" }

    it "can be added for last month, the current month and next month" do
      [ Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1) ].each do |period_start|
        expect(build(:payroll_deduction, employee:, period_start:)).to be_valid, "expected #{period_start} to be open"
      end
    end

    it "can't be added for an older or a later month" do
      [ Date.new(2026, 7, 1), Date.new(2026, 11, 1) ].each do |period_start|
        deduction = build(:payroll_deduction, employee:, period_start:)
        expect(deduction).not_to be_valid
        expect(deduction.errors[:period_start]).to include(message)
      end
    end

    it "can be edited and deleted within the window, including last month" do
      deduction = create(:payroll_deduction, employee:, period_start: Date.new(2026, 8, 1), amount: 5_000)
      expect(deduction.update(amount: 6_000)).to be(true)
      expect(deduction.destroy).to be_truthy
    end

    describe "an entry from a closed month" do
      let(:deduction) do
        create(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 1), amount: 5_000).tap do
          it.update_column(:period_start, Date.new(2026, 7, 1))   # entered back when July was open
        end
      end

      it "can't be edited" do
        expect(deduction.update(amount: 6_000)).to be(false)
        expect(deduction.errors[:period_start]).to include(message)
        expect(deduction.reload.amount).to eq(5_000)
      end

      it "can't be deleted" do
        expect(deduction.destroy).to be(false)
        expect(deduction.errors[:base]).to include("July 2026 is closed: deductions can only be changed for August 2026, September 2026 or October 2026")
        expect(PayrollDeduction.exists?(deduction.id)).to be(true)
      end
    end
  end

  it "stores the month's first day whatever day is given" do
    expect(build(:payroll_deduction, employee:, period_start: Date.new(2026, 9, 17)).period_start).to eq(september)
  end

  it "is allowed for an exited employee's employed months" do
    employee.update!(employment_end_date: Date.new(2026, 9, 20), exit_reason: "resignation")   # exited on the 28th
    expect(employee).to be_exited
    expect(unpaid("2")).to be_valid
  end

  it "refuses an employee from another organization" do
    deduction = build(:payroll_deduction, employee:, organization: create(:organization))
    expect(deduction).not_to be_valid
  end

  it "uses optimistic locking" do
    deduction = create(:payroll_deduction, employee:, period_start: september)
    stale = PayrollDeduction.find(deduction.id)
    deduction.update!(amount: 6_000)
    expect { stale.update!(amount: 7_000) }.to raise_error(ActiveRecord::StaleObjectError)
  end
end
