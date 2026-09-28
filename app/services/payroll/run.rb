module Payroll
  # A country's payroll for one month: every roster employee's MonthlyPay, the summary shown before download and its
  # warnings. Everything is loaded in a handful of queries for the whole roster and grouped in Ruby.
  #
  #   run = Payroll::Run.new(Current.organization, country, Payroll::Month.parse("2026-09"))
  #   run.lines; run.summary; run.warnings
  class Run
    Summary = Data.define(:headcount, :joiners, :leavers, :pay_changes, :gross, :unpaid_leave, :other_deductions, :net) do
      def deductions = unpaid_leave + other_deductions
    end
    Warning = Data.define(:message, :employees)

    attr_reader :organization, :country, :month

    def initialize(organization, country, month)
      @organization = organization
      @country = country
      @month = month
    end

    def lines
      @lines ||= begin
        roster = Roster.employees(organization, country, month)
        revisions = SalaryRevision.where(employee_id: roster.select(:id)).to_a.group_by(&:employee_id)
        deductions = PayrollDeduction.where(employee_id: roster.select(:id), period_start: month.start).to_a.group_by(&:employee_id)
        structures = organization.pay_structures.where(country:).includes(:allowances, :organization).index_by(&:job_role_id)
        country_allowances = organization.country_allowances.where(country:).to_a

        roster.order(:employee_code).map do |employee|
          MonthlyPay.new(employee:, month:, revisions: revisions.fetch(employee.id, []),
                         structure: structures.fetch(employee.job_role_id), country_allowances:,
                         deductions: deductions.fetch(employee.id, []))
        end
      end
    end

    def summary
      @summary ||= Summary.new(
        headcount: lines.size,
        joiners: lines.count { it.period_status.in?(%w[joined joined_and_left]) },
        leavers: lines.count { it.period_status.in?(%w[left joined_and_left]) },
        pay_changes: lines.count { it.pay_changes_count.positive? },
        gross: lines.sum(&:gross), unpaid_leave: lines.sum(&:unpaid_leave_deduction),
        other_deductions: lines.sum(&:other_deductions), net: lines.sum(&:net)
      )
    end

    def warnings
      @warnings ||= [].tap do |warnings|
        negative = lines.select(&:negative_net?)
        if negative.any?
          warnings << Warning.new(message: "#{negative.size} #{negative.one? ? 'row has' : 'rows have'} a negative net salary",
                                  employees: negative.map(&:employee))
        end
        if last_export && last_export.sha256 != CsvExport.new(self).sha256
          warnings << Warning.new(message: "Data has changed since #{month.label} was last exported: this file will " \
                                           "differ from the one sent before", employees: [])
        end
      end
    end

    def last_export = @last_export ||= organization.payroll_exports.where(country:, period_start: month.start).order(:created_at).last
  end
end
