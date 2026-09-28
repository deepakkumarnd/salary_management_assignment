module Payroll
  # What is owed (or recoverable) for earlier months because salary revisions were recorded or voided after payroll
  # was last sent (DESIGN §7.3).
  #
  # Cutoff T = when the previous month was last exported for this country (payroll paid what it was sent), or the start
  # of this month if it never was. For each employee with a revision recorded or voided after T and effective before
  # this month, every earlier month they were employed in, from the earliest such revision up to last month, adds:
  #
  #   monthly gross with the history known now − monthly gross with the history known at T
  #
  # Both sides use today's policy percentages, so only revisions create arrears, never a policy change. Arrears can be
  # negative (e.g. a raise voided after it was paid).
  #
  # Only months from the country's first payroll export onwards count: earlier months were never sent through this
  # system (e.g. people loaded at go-live with old hire dates), so there is nothing to correct. With no export yet,
  # there are no arrears at all.
  class Arrears
    Result = Data.define(:amount, :from, :to) do
      def any? = !amount.zero?
    end
    NONE = Result.new(amount: 0, from: nil, to: nil)

    attr_reader :cutoff

    def initialize(organization:, country:, month:)
      @month = month
      exports = organization.payroll_exports.where(country:)
      @cutoff = exports.where(period_start: month.previous.start).maximum(:created_at) || month.start.in_time_zone.beginning_of_day
      @first_exported = exports.minimum(:period_start)&.then { Month.containing(it) }
    end

    # Whether anything was ever exported for this country (before that, there are no arrears).
    def any_export? = !@first_exported.nil?

    # Whether the cutoff is a real export (false: the previous month was never exported).
    def previous_month_exported? = @cutoff != @month.start.in_time_zone.beginning_of_day

    def for(employee:, revisions:, structure:, country_allowances:)
      return NONE if @first_exported.nil?

      changed = revisions.select { changed_after_cutoff?(it) && it.effective_on < @month.start }
      return NONE if changed.empty?

      known_now = revisions.reject(&:voided?)
      known_then = revisions.select { known_at_cutoff?(it) }
      differences = months_from([ Month.containing(changed.map(&:effective_on).min), @first_exported ].max).filter_map do |month|
        now = MonthlyPay.components(employee:, month:, revisions: known_now, structure:, country_allowances:).values.sum
        before = MonthlyPay.components(employee:, month:, revisions: known_then, structure:, country_allowances:).values.sum
        [ month, now - before ] unless now == before
      end
      return NONE if differences.empty?

      Result.new(amount: differences.sum(&:last), from: differences.first.first, to: differences.last.first)
    end

    private

    def changed_after_cutoff?(revision) = revision.created_at > @cutoff || (revision.voided_at && revision.voided_at > @cutoff)

    def known_at_cutoff?(revision) = revision.created_at <= @cutoff && (revision.voided_at.nil? || revision.voided_at > @cutoff)

    def months_from(first)
      months = []
      month = first
      while month < @month
        months << month
        month = month.next
      end
      months
    end
  end
end
