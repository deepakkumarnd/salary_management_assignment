require "rails_helper"

RSpec.describe Payroll::Month do
  let(:september) { described_class.new(Date.new(2026, 9, 1)) }

  it "parses YYYY-MM and rejects anything else" do
    expect(described_class.parse("2026-09")).to eq(september)
    expect(described_class.parse("2026-9")).to be_nil
    expect(described_class.parse("2026-13")).to be_nil
    expect(described_class.parse("nonsense")).to be_nil
    expect(described_class.parse(nil)).to be_nil
  end

  it "knows its days, bounds, neighbours and label" do
    expect(september).to have_attributes(finish: Date.new(2026, 9, 30), days: 30, to_param: "2026-09", label: "September 2026")
    expect(september.previous).to eq(described_class.new(Date.new(2026, 8, 1)))
    expect(described_class.containing(Date.new(2024, 2, 17))).to have_attributes(days: 29)
  end

  it "compares by date, and never equals something that isn't a month" do
    expect(september).to be > september.previous
    expect(september).not_to eq(nil)
    expect([ september ]).not_to include(nil)
  end

  describe "#employed_range" do
    let(:employee) { build(:employee, hire_date: Date.new(2024, 4, 1)) }

    it "is the whole month for someone employed throughout" do
      expect(september.employed_range(employee)).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
    end

    it "starts on the hire date and ends on the last working day" do
      employee.hire_date = Date.new(2026, 9, 16)
      employee.employment_end_date = Date.new(2026, 9, 20)
      expect(september.employed_range(employee)).to eq(Date.new(2026, 9, 16)..Date.new(2026, 9, 20))
    end

    it "is nil when not employed in the month" do
      employee.employment_end_date = Date.new(2026, 8, 31)
      expect(september.employed_range(employee)).to be_nil
      expect(described_class.new(Date.new(2024, 3, 1)).employed_range(build(:employee, hire_date: Date.new(2024, 4, 1)))).to be_nil
    end
  end
end
