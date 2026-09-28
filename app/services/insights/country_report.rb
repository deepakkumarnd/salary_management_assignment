module Insights
  # "How do we pay people in this country?": current employees' basic, gross and total target pay as of today, for the
  # whole country and by job role and department, in the country's currency.
  #
  # Current = employed today (Active + Leaving), leaving out records ended as "recorded in error". The rows come from
  # one query (basic as of today via the salary-revisions subquery); pay structures and allowances are loaded once and
  # PayCalculator runs in Ruby, so the rounding rules live in one place. Milliseconds at 10k employees.
  #
  #   report = Insights::CountryReport.new(Current.organization, country)
  #   report.summary.gross.median
  #   report.by_job_role.each { |group| group.name; group.headcount; group.total_target.max }
  class CountryReport
    Group = Data.define(:name, :headcount, :basic, :gross, :total_target)
    Row = Data.define(:job_role_id, :department_id, :basic, :gross, :total_target)

    attr_reader :organization, :country, :today

    def initialize(organization, country, today: Date.current)
      @organization = organization
      @country = country
      @today = today
    end

    def summary = @summary ||= group("All employees", rows)

    def by_job_role = @by_job_role ||= breakdown(:job_role_id, organization.job_roles)

    def by_department = @by_department ||= breakdown(:department_id, organization.departments)

    private

    def rows
      @rows ||= begin
        structures = organization.pay_structures.where(country:).includes(:allowances, :organization).index_by(&:job_role_id)
        country_allowances = organization.country_allowances.where(country:).to_a

        organization.employees.where(country:).employed_on(today).countable.with_basic_pay_as_of(today)
                    .map { [ it.job_role_id, it.department_id, it.basic_pay ] }
                    .filter_map do |job_role_id, department_id, basic|
                      next if basic.nil?

                      pay = structures.fetch(job_role_id).breakdown_for(basic, country_allowances:)
                      Row.new(job_role_id:, department_id:, basic:, gross: pay.gross, total_target: pay.total_target)
                    end
      end
    end

    def group(name, rows)
      Group.new(name:, headcount: rows.size, basic: SalaryStats.new(rows.map(&:basic)),
                gross: SalaryStats.new(rows.map(&:gross)), total_target: SalaryStats.new(rows.map(&:total_target)))
    end

    # One group per role (or department) with people in it, largest first, then by name.
    def breakdown(key, catalogue)
      names = catalogue.pluck(:id, :name).to_h
      rows.group_by(&key).map { |id, group_rows| group(names.fetch(id), group_rows) }
          .sort_by { [ -it.headcount, it.name.downcase ] }
    end
  end
end
