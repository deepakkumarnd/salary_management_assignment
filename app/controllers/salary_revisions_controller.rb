class SalaryRevisionsController < AuthenticatedController
  include EmployeePage

  before_action :set_employee
  before_action :refuse_if_exited

  def new
    @revision = @employee.salary_revisions.build(effective_on: Date.current, reason: "appraisal",
                                                 basic_pay: @employee.basic_pay_on(@employee.pay_date))
  end

  def create
    recording = SalaryRevisions::Record.new(@employee, by: Current.user, attributes: revision_params)
    @revision = recording.revision
    if recording.call == :saved
      redirect_to employee_path(@employee, tab: "history"), notice: recorded_message
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def revision_params
    params.expect(salary_revision: %i[effective_on basic_pay reason notes])
  end

  def recorded_message
    date = @revision.effective_on.to_fs(:human)
    if @revision.scheduled?
      "Salary revision recorded. It takes effect on #{date}."
    elsif @revision.backdated?
      "Salary revision recorded, backdated to #{date}. Payroll will show arrears for the months before this one."
    else
      "Salary revision recorded, effective #{date}."
    end
  end
end
