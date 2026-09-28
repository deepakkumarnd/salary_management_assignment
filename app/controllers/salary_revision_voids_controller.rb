class SalaryRevisionVoidsController < AuthenticatedController
  include EmployeePage

  before_action :set_employee
  before_action :refuse_if_exited
  before_action :set_revision

  def new
  end

  def create
    case SalaryRevisions::Void.new(@revision, by: Current.user, reason: params.dig(:salary_revision, :void_reason)).call
    when :saved
      redirect_to employee_path(@employee, tab: "history"),
                  notice: "The revision effective #{@revision.effective_on.to_fs(:human)} was voided."
    when :conflict then render :new, status: :conflict
    else render :new, status: :unprocessable_content
    end
  end

  private

  def set_revision
    @revision = @employee.salary_revisions.find(params[:salary_revision_id])
  end
end
