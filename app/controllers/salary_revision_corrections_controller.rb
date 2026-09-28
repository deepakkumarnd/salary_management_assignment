class SalaryRevisionCorrectionsController < AuthenticatedController
  include EmployeePage

  before_action :set_employee
  before_action :refuse_if_exited
  before_action :set_revision

  def new
    @correction = SalaryRevisions::Correct.new(@revision, by: Current.user)
  end

  def create
    @correction = SalaryRevisions::Correct.new(@revision, by: Current.user, void_reason: params.dig(:correction, :void_reason),
                                                          attributes: replacement_params)
    case @correction.call
    when :saved
      redirect_to employee_path(@employee, tab: "history"),
                  notice: "The revision was corrected. The wrong one stays in the history, marked as voided."
    when :conflict then render :new, status: :conflict
    else render :new, status: :unprocessable_content
    end
  end

  private

  def set_revision
    @revision = @employee.salary_revisions.find(params[:salary_revision_id])
  end

  def replacement_params
    params.fetch(:correction, {}).permit(:effective_on, :basic_pay, :reason, :notes)
  end
end
