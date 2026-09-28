require "rails_helper"

RSpec.describe PayCalculator do
  def breakdown(basic_pay: 1_000_000, allowances: [], variable_pay_percent_bp: 0, overtime_percent_bp: 15_000,
                standard_hours_per_week: 40)
    described_class.new(basic_pay:, allowances:, variable_pay_percent_bp:, overtime_percent_bp:,
                        standard_hours_per_week:).breakdown
  end

  it "with no allowances, gross is the basic" do
    result = breakdown(basic_pay: 600_000)

    expect(result.basic).to eq(600_000)
    expect(result.allowances).to be_empty
    expect(result.gross).to eq(600_000)
  end

  it "adds country and role allowances as a % of basic, country ones first" do
    result = breakdown(basic_pay: 1_200_000, allowances: [
      { name: "Special", percent_bp: 1_500, source: :role },
      { name: "HRA", percent_bp: 4_000, source: :country }
    ])

    expect(result.allowances).to eq([
      { name: "HRA", source: :country, percent_bp: 4_000, amount: 480_000 },
      { name: "Special", source: :role, percent_bp: 1_500, amount: 180_000 }
    ])
    expect(result.gross).to eq(1_860_000)
  end

  it "rounds each allowance half up to whole units, so the breakdown adds up to the gross" do
    result = breakdown(basic_pay: 999, allowances: [
      { name: "A", percent_bp: 1_250, source: :country },   # 124.875 → 125
      { name: "B", percent_bp: 1_250, source: :role },      # 124.875 → 125
      { name: "C", percent_bp: 50, source: :role }          #   4.995 →   5
    ])

    expect(result.allowances.map { it[:amount] }).to eq([ 125, 125, 5 ])
    expect(result.gross).to eq(999 + 125 + 125 + 5)
  end

  it "rounds exactly half up" do
    expect(breakdown(basic_pay: 10, allowances: [ { name: "A", percent_bp: 500, source: :country } ])
             .allowances.first[:amount]).to eq(1)   # 0.5 → 1
  end

  describe "variable pay" do
    it "is a % of the rounded gross, and the total is gross + variable" do
      result = breakdown(basic_pay: 999, allowances: [ { name: "A", percent_bp: 1_250, source: :country } ],
                         variable_pay_percent_bp: 1_000)

      expect(result.gross).to eq(1_124)
      expect(result.variable_target).to eq(112)   # 112.4 → 112
      expect(result.total_target).to eq(1_236)
    end

    it "is zero at 0%" do
      result = breakdown(basic_pay: 500_000, variable_pay_percent_bp: 0)
      expect(result.variable_target).to eq(0)
      expect(result.total_target).to eq(result.gross)
    end
  end

  describe "overtime hourly rate" do
    it "is the overtime % of hourly basic, using the organization's weekly hours" do
      # 1,000,000 / (52 × 40) = 480.769… per hour; × 150% = 721.15
      expect(breakdown(basic_pay: 1_000_000, overtime_percent_bp: 15_000).overtime_hourly).to eq(BigDecimal("721.15"))
      # with 35 hours: 1,000,000 / (52 × 35) = 549.45… per hour; × 150% = 824.18
      expect(breakdown(basic_pay: 1_000_000, overtime_percent_bp: 15_000, standard_hours_per_week: 35)
               .overtime_hourly).to eq(BigDecimal("824.18"))
    end

    it "is zero when the overtime rate is 0%" do
      expect(breakdown(overtime_percent_bp: 0).overtime_hourly).to eq(0)
    end
  end

  it "rejects a non-positive basic" do
    expect { breakdown(basic_pay: 0) }.to raise_error(ArgumentError)
  end
end
