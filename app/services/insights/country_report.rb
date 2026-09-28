module Insights
  # "How do we pay people in this country?": current employees' basic, gross and total target pay as of today, for the
  # whole country and by job role and department, in the country's currency.
  #
  # Current = employed today (Active + Leaving), leaving out records ended as "recorded in error". The rows come from
  # one query (basic as of today via the salary-revisions subquery); pay structures and allowances are loaded once and
  # PayCalculator runs in Ruby, so the rounding rules live in one place.
  #
  # Results are cached per organization, country and day. The key includes the organization's pay_data_version,
  # which every change to employees, revisions, pay policy or catalogues bumps (BumpsPayDataVersion), so a cached
  # report is never stale; the date covers what changes by itself overnight (statuses, scheduled revisions).
  #
  #   report = Insights::CountryReport.new(Current.organization, country)
  #   report.summary.gross.median
  #   report.by_job_role.each { |group| group.name; group.headcount; group.total_target.max }
  class CountryReport
    Group = Data.define(:name, :headcount, :basic, :gross, :total_target) do
      # What the group costs per year at target: everyone's gross + target variable pay (overtime isn't recorded,
      # and employer statutory contributions are out of scope). In the country's currency.
      def cost_to_company = total_target.total
    end
    Row = Data.define(:job_role_id, :department_id, :basic, :gross, :total_target)

    CACHE_VERSION = 2           # bump when the shape of the cached results changes (2: totals)
    CACHE_EXPIRY = 1.day        # the key already changes daily; this just clears out old entries

    attr_reader :organization, :country, :today

    def initialize(organization, country, today: Date.current, cache: Rails.cache)
      @organization = organization
      @country = country
      @today = today
      @cache = cache
    end

    def summary = results.fetch(:summary)
    def by_job_role = results.fetch(:by_job_role)
    def by_department = results.fetch(:by_department)

    private

    def results
      @results ||= @cache.fetch(cache_key, expires_in: CACHE_EXPIRY) do
        { summary: group("All employees", rows),
          by_job_role: breakdown(:job_role_id, organization.job_roles),
          by_department: breakdown(:department_id, organization.departments) }
      end
    end

    # Read fresh: the organization in memory may predate changes made during this request.
    def cache_key
      version = Organization.where(id: organization.id).pick(:pay_data_version)
      [ "insights/country_report", CACHE_VERSION, organization.id, country.id, today.iso8601, version ]
    end

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
