class EmployeesController < AuthenticatedController
  include EmployeePage
  include Pagy::Method

  PER_PAGE = 25

  before_action :set_employee, only: %i[show edit update]
  before_action :refuse_if_exited, only: %i[edit update]

  # The URL is the state: /employees?q=priya&country_id=3&status=current&sort=full_name&dir=asc&page=2
  def index
    @today = Date.current
    @search = EmployeeSearch.new(Current.organization, params.permit(*EmployeeSearch::PARAMS), today: @today)
    @pagy, employees = pagy(:offset, @search.results, limit: PER_PAGE, page: [ params[:page].to_i, 1 ].max)
    @employees = employees.to_a
    @pay = PayBreakdowns.new(Current.organization, @employees)   # gross for this page's rows only
    @countries = Current.organization.countries.order(:name)
    @departments = Current.organization.departments.order(:name)
    @job_roles = Current.organization.job_roles.order(:name)
  end

  def show
    load_employee_page
  end

  def new
    @employee = Current.organization.employees.build(hire_date: Date.current, employment_type: "full_time")
    load_form_options
  end

  def create
    @employee = Current.organization.employees.build(create_params.merge(recorded_by: Current.user))
    if @employee.save
      redirect_to employee_path(@employee), notice: "#{@employee.full_name} was added as #{@employee.employee_code}."
    else
      load_form_options
      render :new, status: :unprocessable_content
    end
  end

  def edit
    load_form_options
  end

  def update
    status = update_with_lock(@employee, update_params)
    return redirect_to(employee_path(@employee), notice: "#{@employee.full_name} was updated.") if status == :saved

    load_form_options
    render :edit, status: status == :conflict ? :conflict : :unprocessable_content
  end

  private

  def create_params
    params.expect(employee: %i[full_name email country_id job_role_id department_id employment_type hire_date
                               initial_basic_pay])
  end

  # Country is fixed once hired (a move is a leaver + new hire), and pay changes through salary revisions.
  def update_params
    params.expect(employee: %i[full_name email job_role_id department_id employment_type hire_date lock_version])
  end

  def load_form_options
    @countries = Current.organization.countries.order(:name)
    @job_roles = Current.organization.job_roles.order(:name)
    @departments = Current.organization.departments.order(:name)
    @default_basics = Current.organization.pay_structures.includes(:country)
                             .to_h { [ "#{it.country_id}:#{it.job_role_id}", it ] }
  end
end
