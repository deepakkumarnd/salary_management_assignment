module Payroll
  # One employee's pay for one month (DESIGN §7.2):
  #
  # 1. Split the days employed in the month at every revision that takes effect inside them; each segment has one basic.
  # 2. For basic and each allowance: monthly = round_half_up(Σ annual(segment basic) × days / (12 × days in month)),
  #    with PayCalculator for the annual amounts and Rational arithmetic throughout, rounding once per component.
  # 3. Gross = the sum of the rounded components.
  # 4. Unpaid leave = round_half_up(annual gross on the last employed day / 12 / days in month × days).
  # 5. Net salary = gross − unpaid leave − other deductions (it may be negative; it's flagged).
  #
  # Revisions count from their effective date within the month; nothing is paid for earlier months (no arrears).
  # Variable pay isn't paid monthly and overtime isn't computed.
  class MonthlyPay
    attr_reader :employee, :month, :structure

    def initialize(employee:, month:, revisions:, structure:, country_allowances:, deductions: [])
      @employee = employee
      @month = month
      @revisions = revisions.reject(&:voided?).sort_by(&:effective_on)   # the history as it stands now
      @structure = structure
      @country_allowances = country_allowances
      @deductions = deductions
    end

    # The rounded monthly components: { "basic" => 105_000, "HRA" => 42_000, … }.
    def self.components(employee:, month:, revisions:, structure:, country_allowances:)
      range = month.employed_range(employee)
      return {} if range.nil?

      revisions = revisions.sort_by(&:effective_on)
      starts = ([ range.begin ] + revisions.map(&:effective_on).select { range.begin < it && it <= range.end }).uniq
      totals = Hash.new(0r)
      starts.each_with_index do |from, index|
        to = starts[index + 1]&.prev_day || range.end
        basic = revisions.select { it.effective_on <= from }.last&.basic_pay
        next if basic.nil?

        share = Rational((to - from).to_i + 1, 12 * month.days)
        pay = structure.breakdown_for(basic, country_allowances:)
        totals["basic"] += basic * share
        pay.allowances.each { totals[it[:name]] += it[:amount] * share }
      end
      totals.transform_values { it.round(half: :up) }
    end

    def employed_range = month.employed_range(employee)
    def days_employed = employed_range&.count.to_i

    def components
      @components ||= self.class.components(employee:, month:, revisions: @revisions, structure:,
                                            country_allowances: @country_allowances)
    end

    def basic_monthly = components.fetch("basic", 0)
    def allowance_amounts = components.except("basic")
    def gross = components.values.sum

    # Annual figures in force on the last employed day of the month (values unpaid leave).
    def annual
      return @annual if defined?(@annual)
      basic = employed_range && @revisions.select { it.effective_on <= employed_range.end }.last&.basic_pay
      @annual = basic && structure.breakdown_for(basic, country_allowances: @country_allowances)
    end

    def unpaid_half_days = @deductions.select(&:unpaid_leave?).sum(&:unpaid_half_days)
    def unpaid_leave_days = Rational(unpaid_half_days, 2)

    def unpaid_leave_deduction
      return 0 if unpaid_half_days.zero? || annual.nil?
      Rational(annual.gross * unpaid_half_days, 12 * month.days * 2).round(half: :up)
    end

    def other_deductions = other_entries.sum(&:amount)
    def other_deductions_detail = other_entries.map { "#{it.description}: #{it.amount}" }.join("; ")
    def deductions = unpaid_leave_deduction + other_deductions

    def net = gross - deductions
    def negative_net? = net.negative?

    def period_status
      joined = employee.hire_date.between?(month.start, month.finish)
      left = employee.employment_end_date&.between?(month.start, month.finish)
      if joined && left then "joined_and_left"
      elsif joined then "joined"
      elsif left then "left"
      else "continuing"
      end
    end

    # Pay changes effective on an employed day of the month (the hire itself isn't a change).
    def pay_changes_count
      return 0 if employed_range.nil?
      @revisions.count { !it.hire? && employed_range.cover?(it.effective_on) }
    end

    private

    def other_entries = @deductions.select(&:other?).sort_by(&:id)
  end
end
