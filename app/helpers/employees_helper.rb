module EmployeesHelper
  EMPLOYMENT_TYPES = { "full_time" => "Full time", "part_time" => "Part time", "contractor" => "Contractor" }.freeze
  EXIT_REASONS = {
    "resignation" => "Resignation", "termination" => "Termination", "retirement" => "Retirement",
    "end_of_contract" => "End of contract", "internal_transfer" => "Internal transfer (another country)",
    "recorded_in_error" => "Recorded in error", "other" => "Other"
  }.freeze
  REVISION_REASONS = {
    "hire" => "Hire", "appraisal" => "Appraisal", "promotion" => "Promotion",
    "market_adjustment" => "Market adjustment", "correction" => "Correction"
  }.freeze

  def employment_type_label(type) = EMPLOYMENT_TYPES.fetch(type, type.to_s.humanize)
  def exit_reason_label(reason) = EXIT_REASONS.fetch(reason, reason.to_s.humanize)
  def revision_reason_label(reason) = REVISION_REASONS.fetch(reason, reason.to_s.humanize)

  # Active / Leaving (until 30 Sep) / Exited
  def status_badge(employee, today = Date.current)
    case employee.status(today)
    when :active  then tag.span("Active", class: "badge badge-success badge-sm")
    when :leaving then tag.span("Leaving (until #{employee.employment_end_date.strftime('%-d %b')})", class: "badge badge-warning badge-sm whitespace-nowrap")
    else tag.span("Exited", class: "badge badge-ghost badge-sm")
    end
  end

  # "+₹1,50,000 (+12.5%)" against the previous basic in force; nil when there is nothing to compare with.
  def pay_change(basic_pay, previous, currency_code)
    return if previous.nil? || previous.zero?

    difference = basic_pay - previous
    sign = difference.negative? ? "-" : "+"
    percent = (difference.abs * 100r / previous).round(1)
    "#{sign}#{money(difference.abs, currency_code)} (#{sign}#{format('%.1f', percent)}%)"
  end

  # For the salary history: the basic in force just before each revision took effect (voided rows compare with the
  # history as it stands now).
  def previous_basics(revisions)
    in_force = revisions.reject(&:voided?).sort_by(&:effective_on)
    revisions.to_h do |revision|
      before = in_force.select { it.effective_on < revision.effective_on }.last
      [ revision.id, before&.basic_pay ]
    end
  end
end
