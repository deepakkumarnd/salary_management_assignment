# Loads an employee by code from Current.organization (another organization's code → 404), and everything the employee
# page shows, for controllers that render it (e.g. after a refused "undo exit").
module EmployeePage
  extend ActiveSupport::Concern

  private

  def set_employee
    @employee = Current.organization.employees.includes(:country, :department, :job_role)
                       .find_by!(employee_code: params[:employee_id] || params[:id])
  end

  def load_employee_page
    @today = Date.current
    @pay_date = @employee.pay_date(@today)
    @breakdown = @employee.breakdown_on(@pay_date)
    @next_revision = @employee.next_revision_after(@pay_date) unless @employee.exited?(@today)
    @revisions = @employee.salary_revisions.includes(:created_by, :voided_by).order(effective_on: :desc, created_at: :desc)
  end

  def refuse_if_exited
    return unless @employee.exited?
    redirect_to employee_path(@employee), alert: "#{@employee.full_name} has left, so their record is read-only."
  end
end
