require "csv"

module Payroll
  # The payroll file for a country and month (DESIGN §7.5–7.6): one row per roster employee, employees only.
  # UTF-8 with a BOM and CRLF line endings so Excel opens it cleanly; plain numbers, ISO dates, percentages with two
  # decimals; text that Excel would run as a formula (= + - @ tab CR) is prefixed with an apostrophe.
  class CsvExport
    BOM = "﻿".freeze
    FORMULA_START = /\A[=+\-@\t\r]/

    def initialize(run)
      @run = run
    end

    def filename = "#{@run.organization.name.parameterize}-payroll-#{@run.country.name.parameterize}-#{@run.month.to_param}.csv"
    def row_count = @run.lines.size
    def to_s = @to_s ||= BOM + CSV.generate(row_sep: "\r\n") { |csv| ([ headers ] + rows).each { csv << it } }
    def sha256 = Digest::SHA256.hexdigest(to_s)

    def headers
      %w[employee_id full_name email department job_role employment_type currency
         hire_date last_working_day exit_reason period_status days_in_month days_employed
         basic_pay_annual gross_pay_annual basic_pay_monthly] +
        @run.allowance_columns.map { "allowance_#{it.parameterize(separator: '_')}_monthly" } +
        %w[gross_pay_monthly arrears arrears_from arrears_to unpaid_leave_days unpaid_leave_deduction
           other_deductions other_deductions_detail net_pay_before_tax
           pay_changes_in_month previous_basic_pay_annual pay_change_effective_on pay_change_reason
           variable_pay_percent target_variable_pay_annual overtime_percent overtime_hourly_rate]
    end

    private

    def rows = @run.lines.map { row(it) }.map { |cells| cells.map { safe(it) } }

    def row(line)
      employee = line.employee
      annual = line.annual
      change = line.pay_change
      [
        employee.employee_code, employee.full_name, employee.email, employee.department.name, employee.job_role.name,
        employee.employment_type, @run.country.currency_code,
        employee.hire_date.iso8601, employee.employment_end_date&.iso8601, employee.exit_reason, line.period_status,
        @run.month.days, line.days_employed,
        annual&.basic, annual&.gross, line.basic_monthly,
        *@run.allowance_columns.map { line.allowance_amounts[it] },
        line.gross, line.arrears.amount, line.arrears.from&.start&.iso8601, line.arrears.to&.finish&.iso8601,
        format("%.1f", line.unpaid_leave_days), line.unpaid_leave_deduction,
        line.other_deductions, line.other_deductions_detail.presence, line.net,
        line.pay_changes_count, change&.previous_basic, change&.effective_on&.iso8601, change&.reason,
        PercentAttribute.format(line.structure.variable_pay_percent_bp), annual&.variable_target,
        PercentAttribute.format(line.structure.overtime_percent_bp), annual && format("%.2f", annual.overtime_hourly)
      ]
    end

    # Only text can carry a formula; numbers (including negative ones) are written as numbers.
    def safe(value) = value.is_a?(String) && value.match?(FORMULA_START) ? "'#{value}" : value
  end
end
