# The one place employee-list logic lives: search, filters, status and sorting, always inside one organization.
# Every parameter is optional and they combine with AND. Unknown values fall back to the defaults, so a hand-edited
# URL never errors or leaks data (ids from another organization simply match nothing).
#
#   EmployeeSearch.new(Current.organization, params.permit(*EmployeeSearch::PARAMS), today: Date.current).results
class EmployeeSearch
  PARAMS = %i[q country_id department_id job_role_id status sort dir].freeze

  STATUSES = {
    "current" => { label: "Active + Leaving",
                   scope: ->(scope, today) { scope.where("employees.employment_end_date IS NULL OR employees.employment_end_date >= ?", today) } },
    "active"  => { label: "Active",  scope: ->(scope, _today) { scope.where(employment_end_date: nil) } },
    "leaving" => { label: "Leaving", scope: ->(scope, today) { scope.where(employment_end_date: today..) } },
    "exited"  => { label: "Exited",  scope: ->(scope, today) { scope.where(employment_end_date: ...today).countable } },
    "all"     => { label: "All (including recorded in error)", scope: ->(scope, _today) { scope } }
  }.freeze
  DEFAULT_STATUS = "current"

  # Allow-listed sort columns → SQL. basic_pay is the alias of the "basic as of today" subquery.
  SORTABLE = {
    "employee_code"       => "employees.employee_code",
    "full_name"           => "employees.full_name",
    "country"             => "countries.name",
    "department"          => "departments.name",
    "job_role"            => "job_roles.name",
    "basic_pay"           => "basic_pay",
    "hire_date"           => "employees.hire_date",
    "employment_end_date" => "employees.employment_end_date"
  }.freeze
  DEFAULT_SORT = "employee_code"

  attr_reader :q, :country_id, :department_id, :job_role_id, :status, :sort, :dir

  def initialize(organization, params, today: Date.current)
    @organization = organization
    @today = today
    params = params.to_h.symbolize_keys
    @q = params[:q].to_s.strip.presence
    @country_id, @department_id, @job_role_id = params.values_at(:country_id, :department_id, :job_role_id).map(&:presence)
    @status = params[:status].presence_in(STATUSES.keys) || DEFAULT_STATUS
    @sort = params[:sort].presence_in(SORTABLE.keys) || DEFAULT_SORT
    @dir = params[:dir] == "desc" ? "desc" : "asc"
  end

  def results
    scope = @organization.employees.joins(:country, :department, :job_role)
                         .includes(:country, :department, :job_role).with_basic_pay_as_of(@today)
    scope = scope.where(country_id:)    if country_id
    scope = scope.where(department_id:) if department_id
    scope = scope.where(job_role_id:)   if job_role_id
    scope = STATUSES.fetch(status)[:scope].call(scope, @today)
    scope = scope.where(<<~SQL.squish, term: "%#{Employee.sanitize_sql_like(q)}%") if q
      employees.full_name LIKE :term ESCAPE '\\' OR employees.email LIKE :term ESCAPE '\\'
      OR employees.employee_code LIKE :term ESCAPE '\\'
    SQL
    column = Arel.sql(SORTABLE.fetch(sort))                          # allow-listed SQL, never user input
    order = [ dir == "desc" ? column.desc : column.asc ]
    order << Employee.arel_table[:employee_code].asc unless sort == DEFAULT_SORT   # stable pages when values tie
    scope.order(*order)
  end

  # The chosen filters, for badges ("✕" removes one) and the empty-state message.
  def active_filters
    filters = []
    filters << { key: :q, label: "“#{q}”" } if q
    { country_id: @organization.countries, department_id: @organization.departments, job_role_id: @organization.job_roles }
      .each do |key, records|
        id = public_send(key)
        name = id && records.find_by(id:)&.name
        filters << { key:, label: name } if name
      end
    filters << { key: :status, label: STATUSES.fetch(status)[:label] } if status != DEFAULT_STATUS
    filters
  end

  # The query parameters behind this search, for links that keep it (sorting, paging, removing one filter).
  def to_params
    { q:, country_id:, department_id:, job_role_id:, status: (status if status != DEFAULT_STATUS),
      sort: (sort if sort != DEFAULT_SORT), dir: (dir if dir == "desc") }.compact
  end
end
