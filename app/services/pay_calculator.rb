require "bigdecimal/util"

# The single source of truth for pay amounts (employee page, previews, lists, insights, payroll export).
# All percentages are basis points (4000 = 40.00%); money is whole units of local currency. It knows nothing about
# dates: callers pass the basic pay as of the day they care about.
#
#   PayCalculator.new(basic_pay: 1_200_000, allowances: [{ name: "HRA", percent_bp: 4_000, source: :country }],
#                     variable_pay_percent_bp: 1_000, overtime_percent_bp: 15_000, standard_hours_per_week: 40).breakdown
class PayCalculator
  Breakdown = Data.define(:basic, :allowances, :gross, :variable_target, :total_target, :overtime_hourly)

  SOURCE_ORDER = { country: 0, role: 1 }.freeze
  WEEKS_PER_YEAR = 52

  def initialize(basic_pay:, allowances:, variable_pay_percent_bp:, overtime_percent_bp:, standard_hours_per_week:)
    raise ArgumentError, "basic pay must be a positive whole number" unless basic_pay.is_a?(Integer) && basic_pay.positive?

    @basic_pay = basic_pay
    @allowances = allowances
    @variable_pay_percent_bp = variable_pay_percent_bp
    @overtime_percent_bp = overtime_percent_bp
    @standard_hours_per_week = standard_hours_per_week
  end

  def breakdown
    # Rounded per allowance, then summed, so the lines always add up to the gross.
    lines = @allowances.sort_by { [ SOURCE_ORDER.fetch(it[:source]), it[:name].downcase ] }.map do |allowance|
      { name: allowance[:name], source: allowance[:source], percent_bp: allowance[:percent_bp],
        amount: percent_of(@basic_pay, allowance[:percent_bp]) }
    end
    gross = @basic_pay + lines.sum { it[:amount] }
    variable_target = percent_of(gross, @variable_pay_percent_bp)   # target at 100% performance

    Breakdown.new(basic: @basic_pay, allowances: lines, gross:, variable_target:,
                  total_target: gross + variable_target, overtime_hourly:)
  end

  private

  # amount × percentage, rounded to whole units, halves up (124.875 → 125, 0.5 → 1). Basis points: 10_000 = 100%.
  # 10_000r is a Rational, so the division is exact and the only rounding is the one named here.
  def percent_of(amount, basis_points) = (amount * basis_points / 10_000r).round(half: :up)

  def overtime_hourly
    hourly_basic = Rational(@basic_pay, WEEKS_PER_YEAR * @standard_hours_per_week)
    (hourly_basic * @overtime_percent_bp / 10_000).round(2, half: :up).to_d(20)
  end
end
