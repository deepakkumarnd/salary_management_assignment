require "csv"

module Payroll
  # The payroll file for a country and month: one row per roster employee (employees only), with
  #
  #   employee_id, employee_name, gross_salary, deductions, net_salary
  #
  # for the month, where net_salary = gross_salary − deductions (unpaid leave + other deductions). UTF-8 with a BOM and
  # CRLF line endings so Excel opens it cleanly; plain numbers; text that Excel would run as a formula (= + - @ tab CR)
  # is prefixed with an apostrophe.
  class CsvExport
    BOM = "﻿".freeze
    FORMULA_START = /\A[=+\-@\t\r]/
    HEADERS = %w[employee_id employee_name gross_salary deductions net_salary].freeze

    def initialize(run)
      @run = run
    end

    def filename = "#{@run.organization.name.parameterize}-payroll-#{@run.country.name.parameterize}-#{@run.month.to_param}.csv"
    def row_count = @run.lines.size
    def to_s = @to_s ||= BOM + CSV.generate(row_sep: "\r\n") { |csv| ([ HEADERS ] + rows).each { csv << it } }
    def sha256 = Digest::SHA256.hexdigest(to_s)

    private

    def rows
      @run.lines.map do |line|
        [ line.employee.employee_code, line.employee.full_name, line.gross, line.deductions, line.net ].map { safe(it) }
      end
    end

    # Only text can carry a formula; numbers (including negative ones) are written as numbers.
    def safe(value) = value.is_a?(String) && value.match?(FORMULA_START) ? "'#{value}" : value
  end
end
