module Payroll
  # A country's payroll for one month: every roster employee's MonthlyPay (with arrears), the summary shown before
  # download and its warnings. Everything is loaded in a handful of queries for the whole roster and grouped in Ruby.
  #
  #   run = Payroll::Run.new(Current.organization, country, Payroll::Month.parse("2026-09"))
  #   run.lines; run.summary; run.warnings
  class Run
    Summary = Data.define(:headcount, :joiners, :leavers, :pay_changes, :with_arrears,
                          :gross, :arrears, :unpaid_leave, :other_deductions, :net)
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

        roster.includes(:department, :job_role).order(:employee_code).map do |employee|
          employee_revisions = revisions.fetch(employee.id, [])
          structure = structures.fetch(employee.job_role_id)
          arrears = arrears_calculator.for(employee:, revisions: employee_revisions, structure:, country_allowances:)
          MonthlyPay.new(employee:, month:, revisions: employee_revisions, structure:, country_allowances:,
                         deductions: deductions.fetch(employee.id, []), arrears:)
        end
      end
    end

    # One CSV column per allowance in the country: country allowances first, then role allowances, each alphabetical.
    def allowance_columns
      @allowance_columns ||= begin
        country_names = organization.country_allowances.where(country:).pluck(:name).sort_by(&:downcase)
        role_names = PayStructureAllowance.joins(:pay_structure).where(pay_structures: { organization_id: organization.id, country_id: country.id })
                                          .distinct.pluck(:name).sort_by(&:downcase)
        country_names + (role_names - country_names)
      end
    end

    def summary
      @summary ||= Summary.new(
        headcount: lines.size,
        joiners: lines.count { it.period_status.in?(%w[joined joined_and_left]) },
        leavers: lines.count { it.period_status.in?(%w[left joined_and_left]) },
        pay_changes: lines.count { it.pay_changes_count.positive? },
        with_arrears: lines.count { it.arrears.any? },
        gross: lines.sum(&:gross), arrears: lines.sum { it.arrears.amount },
        unpaid_leave: lines.sum(&:unpaid_leave_deduction), other_deductions: lines.sum(&:other_deductions),
        net: lines.sum(&:net)
      )
    end

    def warnings
      @warnings ||= [].tap do |warnings|
        negative = lines.select(&:negative_net?)
        if negative.any?
          warnings << Warning.new(message: "#{negative.size} #{negative.one? ? 'row has' : 'rows have'} a negative net pay",
                                  employees: negative.map(&:employee))
        end
        if !arrears_calculator.any_export?
          warnings << Warning.new(message: "Nothing has been exported for #{country.name} yet, so this file has no arrears: " \
                                           "they start once payroll files are being sent", employees: [])
        elsif !arrears_calculator.previous_month_exported?
          warnings << Warning.new(message: "#{month.previous.label} was never exported for #{country.name}, so arrears " \
                                           "only cover changes made since #{month.start.to_fs(:human)}", employees: [])
        end
        if last_export && last_export.sha256 != CsvExport.new(self).sha256
          warnings << Warning.new(message: "Data has changed since #{month.label} was last exported: this file will " \
                                           "differ from the one sent before", employees: [])
        end
      end
    end

    def last_export = @last_export ||= organization.payroll_exports.where(country:, period_start: month.start).order(:created_at).last

    private

    def arrears_calculator = @arrears_calculator ||= Arrears.new(organization:, country:, month:)
  end
end
