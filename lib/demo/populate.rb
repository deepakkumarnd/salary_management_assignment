module Demo
  # Fills an organization with realistic data at scale, for demos and performance checks (DESIGN §9):
  #
  #   bin/rails demo:populate ORG="ACME" EMPLOYEES=10000
  #
  # - Setup still pending: applies standard defaults (all countries, HRA 40% in India, suggested departments and roles)
  #   and completes it. Otherwise uses what HR configured.
  # - A pay structure for every operating country + role that lacks one, with local-currency defaults and variable pay
  #   (10% for most roles, 15% for managers, 30–50% for sales).
  # - Employees with hire dates over the last six years and IDs reserved as one block from the organization's counter,
  #   so they continue the sequence used in the UI; a hire revision each, a yearly appraisal every 1 April, some
  #   promotions, a handful of backdated entries made this month (at least one per country) and some raises
  #   scheduled for next April.
  # - About 12% leavers, 1% serving notice and a few records ended as "recorded in error".
  # - Deductions for last month and this month, and payroll export log entries for the last six months.
  #
  # Rows are written with insert_all in batches (seconds for 10k employees), so this class upholds the models' rules
  # itself; the specs check the result against the models' validations. Deterministic: the same organization setup
  # always gets the same data.
  class Populate
    SEED = 42
    BATCH = 1_000

    # Mid-level annual basic in local currency, and what it's rounded to.
    COUNTRY_BASE = {
      "India" => [ 1_200_000, 10_000 ], "United States" => [ 110_000, 1_000 ], "United Kingdom" => [ 60_000, 1_000 ],
      "Germany" => [ 65_000, 1_000 ], "Canada" => [ 90_000, 1_000 ], "Australia" => [ 110_000, 1_000 ],
      "Singapore" => [ 85_000, 1_000 ], "Japan" => [ 7_000_000, 100_000 ]
    }.freeze
    COUNTRY_WEIGHT = {
      "India" => 40, "United States" => 20, "United Kingdom" => 10, "Germany" => 8, "Canada" => 7, "Australia" => 5,
      "Singapore" => 5, "Japan" => 5
    }.freeze

    # role => [pay multiplier of the country base, hiring weight, department]
    ROLES = {
      "Software Engineer" => [ 1.0, 18, "Engineering" ], "Senior Software Engineer" => [ 1.4, 10, "Engineering" ],
      "Engineering Manager" => [ 1.6, 3, "Engineering" ], "Data Analyst" => [ 0.85, 5, "Engineering" ],
      "Product Manager" => [ 1.4, 4, "Product" ], "Designer" => [ 0.8, 4, "Product" ],
      "Sales Executive" => [ 0.8, 12, "Sales" ], "Account Manager" => [ 0.9, 6, "Sales" ],
      "Customer Support Specialist" => [ 0.5, 12, "Customer Support" ], "Marketing Specialist" => [ 0.75, 5, "Marketing" ],
      "Accountant" => [ 0.7, 5, "Finance" ], "Finance Manager" => [ 1.3, 2, "Finance" ],
      "HR Generalist" => [ 0.65, 3, "Human Resources" ], "Recruiter" => [ 0.65, 3, "Human Resources" ],
      "Operations Manager" => [ 1.1, 3, "Operations" ]
    }.freeze

    EXIT_REASONS = { "resignation" => 60, "termination" => 10, "end_of_contract" => 10, "retirement" => 5,
                     "internal_transfer" => 5, "other" => 10 }.freeze
    EMPLOYMENT_TYPES = { "full_time" => 85, "part_time" => 10, "contractor" => 5 }.freeze
    EXPORTED_MONTHS = 6

    Person = Struct.new(:code, :full_name, :email, :country, :job_role, :department, :employment_type, :hire_date,
                        :end_date, :exit_reason, :revisions, keyword_init: true)
    Revision = Struct.new(:effective_on, :basic_pay, :reason, :notes, :created_at, keyword_init: true)

    def initialize(organization, employees: 10_000, today: Date.current)
      @organization = organization
      @count = employees
      @today = today
      @random = Random.new(SEED)
      @author = organization.users.active.order(:id).first or
        raise ArgumentError, "#{organization.name} has no active HR user to author the salary history; run db:seed first"
    end

    def call
      with_faker_seed do
        ActiveRecord::Base.transaction do
          complete_setup unless @organization.setup_completed?
          create_pay_structures
          people = build_people
          add_backdated_adjustments(people)
          insert_employees(people)
          insert_revisions(people)
          insert_deductions(people)
          log_exports(people)
          Organization.bump_pay_data_version(@organization.id)   # insert_all skips callbacks
        end
      end
      @count
    end

    private

    # --- setup and policy -------------------------------------------------------------------------------------

    def complete_setup
      @organization.update_operating_countries(Country.ids) or raise ActiveRecord::RecordInvalid, @organization
      india = Country.find_by(name: "India")
      if india && !@organization.country_allowances.exists?(country: india, name: "HRA")
        @organization.country_allowances.create!(country: india, name: "HRA", percent: "40")
      end
      Onboarding::CatalogueForm.new(@organization).then do |catalogue|
        next if @organization.departments.exists? && @organization.job_roles.exists?
        catalogue.save or raise ActiveRecord::RecordInvalid, catalogue
      end
      @organization.update!(setup_completed_at: Time.current)
    end

    def create_pay_structures
      existing = @organization.pay_structures.pluck(:country_id, :job_role_id).to_set
      @organization.countries.each do |country|
        base, unit = COUNTRY_BASE.fetch(country.name) { [ 100_000, 1_000 ] }
        @organization.job_roles.each do |role|
          next if existing.include?([ country.id, role.id ])

          multiplier = ROLES.dig(role.name, 0) || 1.0
          @organization.pay_structures.create!(
            country:, job_role: role, default_basic_pay: round_to(base * multiplier, unit),
            variable_pay_percent_bp: variable_pay_bp(role.name), overtime_percent_bp: 15_000
          )
        end
      end
    end

    def variable_pay_bp(role_name)
      if role_name.match?(/sales|account manager/i) then @random.rand(30..50) * 100
      elsif role_name.match?(/manager/i) then 1_500
      else 1_000
      end
    end

    # --- people -----------------------------------------------------------------------------------------------

    def build_people
      countries = @organization.countries.to_a
      roles = @organization.job_roles.to_a
      departments = @organization.departments.index_by(&:name)
      structures = @organization.pay_structures.includes(:country).index_by { [ it.country_id, it.job_role_id ] }
      units = countries.to_h { [ it.id, COUNTRY_BASE.dig(it.name, 1) || 1_000 ] }
      numbers = EmployeeCode.reserve(@organization, @count)   # continues the sequence used in the UI

      Array.new(@count) do |index|
        country = weighted(countries.to_h { [ it, COUNTRY_WEIGHT.fetch(it.name, 5) ] })
        role = weighted(roles.to_h { [ it, ROLES.dig(it.name, 1) || 5 ] })
        department = departments[ROLES.dig(role.name, 2)] || departments.values[@random.rand(departments.size)]
        number = numbers.begin + index
        first_name = Faker::Name.first_name
        last_name = Faker::Name.last_name
        hire_date = @today - @random.rand(0..(6 * 365))
        end_date, exit_reason = exit_for(hire_date)
        unit = units.fetch(country.id)
        starting = round_to(structures.fetch([ country.id, role.id ]).default_basic_pay * @random.rand(0.75..1.25), unit)

        Person.new(
          code: EmployeeCode.format_for(@organization, number),
          full_name: "#{first_name} #{last_name}",
          email: "#{first_name}.#{last_name}.#{number}@#{@organization.name.parameterize}.test".downcase.delete("'"),
          country:, job_role: role, department:, employment_type: weighted(EMPLOYMENT_TYPES), hire_date:,
          end_date:, exit_reason:, revisions: salary_history(hire_date, end_date, exit_reason, starting, unit)
        )
      end
    end

    # About 12% have left, 1% are serving notice (leaving in the next 60 days), 0.5% were recorded in error.
    def exit_for(hire_date)
      roll = @random.rand
      if roll < 0.005
        [ hire_date, "recorded_in_error" ]
      elsif roll < 0.125 && hire_date < @today - 90
        [ hire_date + @random.rand(60..(@today - hire_date - 1).to_i), weighted(EXIT_REASONS) ]
      elsif roll < 0.135
        [ @today + @random.rand(1..60), "resignation" ]
      else
        [ nil, nil ]
      end
    end

    def salary_history(hire_date, end_date, exit_reason, starting, unit)
      history = [ Revision.new(effective_on: hire_date, basic_pay: starting, reason: "hire", created_at: at(hire_date)) ]
      return history if exit_reason == "recorded_in_error"

      last_day = [ end_date, @today ].compact.min
      basic = starting

      # A yearly appraisal every 1 April after the hire date, entered in its own week.
      april = Date.new(hire_date.year, 4, 1)
      april = april.next_year if april <= hire_date
      while april <= last_day
        basic = round_to(basic * @random.rand(1.03..1.12), unit)
        history << Revision.new(effective_on: april, basic_pay: basic, reason: "appraisal", created_at: at(april + @random.rand(0..6)))
        april = april.next_year
      end

      # About 5% promoted at some point after their first year.
      if @random.rand < 0.05 && hire_date + 365 < last_day
        date = hire_date + @random.rand(366..(last_day - hire_date).to_i)
        unless history.any? { it.effective_on == date }
          previous = history.select { it.effective_on < date }.max_by(&:effective_on).basic_pay
          history << Revision.new(effective_on: date, basic_pay: round_to(previous * @random.rand(1.15..1.25), unit),
                                  reason: "promotion", notes: "Promoted", created_at: at(date + @random.rand(0..6)))
        end
      end

      # About 10% of people staying on have a raise scheduled for next April, entered this month.
      next_april = april
      if end_date.nil? && @random.rand < 0.10 && next_april > @today
        latest = history.max_by(&:effective_on).basic_pay
        history << Revision.new(effective_on: next_april, basic_pay: round_to(latest * @random.rand(1.04..1.10), unit),
                                reason: "appraisal", notes: "Scheduled appraisal", created_at: Time.current)
      end

      history.sort_by(&:effective_on)
    end

    # A handful of backdated adjustments, entered this month but effective one to four months ago (they show as
    # "Backdated" in the salary history): 1 in 200 current employees, and at least one in every country.
    def add_backdated_adjustments(people)
      people.select { it.end_date.nil? }.group_by(&:country).each_value do |group|
        group.shuffle(random: @random).first([ group.size / 200, 1 ].max).each do |person|
          date = @today.beginning_of_month << @random.rand(1..4)
          next if date <= person.hire_date || person.revisions.any? { it.effective_on == date }

          previous = person.revisions.select { it.effective_on < date }.max_by(&:effective_on).basic_pay
          unit = COUNTRY_BASE.dig(person.country.name, 1) || 1_000
          person.revisions << Revision.new(effective_on: date, basic_pay: round_to(previous * 1.05, unit), reason: "market_adjustment",
                                           notes: "Backdated market adjustment", created_at: Time.current)
          person.revisions.sort_by!(&:effective_on)
        end
      end
    end

    # --- writes -----------------------------------------------------------------------------------------------

    def insert_employees(people)
      rows = people.map do |person|
        created = at(person.hire_date)
        { organization_id: @organization.id, employee_code: person.code, full_name: person.full_name, email: person.email,
          country_id: person.country.id, job_role_id: person.job_role.id, department_id: person.department.id,
          employment_type: person.employment_type, hire_date: person.hire_date, employment_end_date: person.end_date,
          exit_reason: person.exit_reason, created_at: created, updated_at: created }
      end
      @employee_ids = {}
      rows.each_slice(BATCH) do |batch|
        Employee.insert_all!(batch, returning: %w[id employee_code], record_timestamps: false)
                .each { @employee_ids[it["employee_code"]] = it["id"] }
      end
    end

    def insert_revisions(people)
      rows = people.flat_map do |person|
        person.revisions.map do |revision|
          { organization_id: @organization.id, employee_id: @employee_ids.fetch(person.code),
            effective_on: revision.effective_on, basic_pay: revision.basic_pay, reason: revision.reason,
            notes: revision.notes, created_by_id: @author.id, created_at: revision.created_at, updated_at: revision.created_at }
        end
      end
      rows.each_slice(BATCH) { SalaryRevision.insert_all!(it, record_timestamps: false) }
    end

    # Last month and this month: about 8% with 0.5–3 unpaid days, 1% with a salary advance recovery.
    def insert_deductions(people)
      rows = [ Payroll::Month.containing(@today).previous, Payroll::Month.containing(@today) ].flat_map do |month|
        people.filter_map do |person|
          next if person.exit_reason == "recorded_in_error"

          days = days_employed(person, month)
          next if days.zero?

          roll = @random.rand
          base = { organization_id: @organization.id, employee_id: @employee_ids.fetch(person.code), period_start: month.start,
                   created_by_id: @author.id, unpaid_half_days: nil, amount: nil, description: nil }
          if roll < 0.08
            base.merge(kind: "unpaid_leave", unpaid_half_days: [ @random.rand(1..6), days * 2 ].min)
          elsif roll < 0.09
            monthly = person.revisions.select { it.effective_on <= month.finish }.max_by(&:effective_on).basic_pay / 12
            base.merge(kind: "other", amount: [ round_to(monthly * 0.2, 100), 100 ].max, description: "Salary advance recovery")
          end
        end
      end
      rows.each_slice(BATCH) { PayrollDeduction.insert_all!(it) }
    end

    # Payroll has been sent for the last six months: an export log entry on the 25th of each, per country.
    def log_exports(people)
      rows = @organization.countries.flat_map do |country|
        month = Payroll::Month.containing(@today)
        Array.new(EXPORTED_MONTHS) do
          month = month.previous
          headcount = people.count { it.country == country && it.exit_reason != "recorded_in_error" && days_employed(it, month).positive? }
          exported_at = Time.utc(month.start.year, month.start.month, 25, 10)
          { organization_id: @organization.id, country_id: country.id, period_start: month.start, row_count: headcount,
            sha256: Digest::SHA256.hexdigest("demo #{country.name} #{month.to_param}"), exported_by_id: @author.id,
            created_at: exported_at }
        end
      end
      PayrollExport.insert_all!(rows, record_timestamps: false) if rows.any?
    end

    # --- helpers ----------------------------------------------------------------------------------------------

    def days_employed(person, month)
      from = [ person.hire_date, month.start ].max
      to = [ person.end_date || month.finish, month.finish ].min
      from <= to ? (to - from).to_i + 1 : 0
    end

    def weighted(weights)
      total = weights.values.sum
      pick = @random.rand * total
      weights.each { |item, weight| return item if (pick -= weight) < 0 }
      weights.keys.last
    end

    def round_to(amount, unit) = [ (amount / unit).round * unit, unit ].max.to_i

    # A time on that day, never in the future.
    def at(date) = [ Time.utc(date.year, date.month, date.day, 9) + @random.rand(0..(8 * 3600)), Time.current ].min

    def with_faker_seed
      previous = Faker::Config.random
      Faker::Config.random = Random.new(SEED)
      yield
    ensure
      Faker::Config.random = previous
    end
  end
end
