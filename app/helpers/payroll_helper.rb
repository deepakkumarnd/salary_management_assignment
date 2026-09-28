module PayrollHelper
  def deduction_row_id(employee, month) = "deductions_#{employee.id}_#{month.to_param}"
  def deduction_totals_id(country_id, month) = "deduction_totals_#{country_id}_#{month.to_param}"

  # The months shown on an employee's Deductions tab: next month if they're still employed then, the last three they
  # were employed in, and any month that has deductions, newest first.
  def deduction_months(employee, deductions)
    upcoming = Payroll::Month.containing(Date.current).next
    upcoming = nil unless upcoming.employed_range(employee)
    last = Payroll::Month.containing([ employee.employment_end_date || Date.current, Date.current ].min)
    recent = []
    month = last
    while recent.size < 3 && month.start >= employee.hire_date.beginning_of_month
      recent << month
      month = month.previous
    end
    ([ upcoming ].compact + recent + deductions.map(&:month)).uniq.sort.reverse
  end
end
