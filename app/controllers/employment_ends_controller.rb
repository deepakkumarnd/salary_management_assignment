# Ending employment (create) and undoing an exit (destroy). Both are updates to the employee, so both carry the
# lock_version the user saw and are refused with 409 if someone changed the employee in the meantime.
class EmploymentEndsController < AuthenticatedController
  include EmployeePage

  before_action :set_employee
  before_action :refuse_if_exit_recorded, only: %i[new create]

  def new
    @scheduled = scheduled_revisions
  end

  def create
    ending = Employment::End.new(@employee, by: Current.user, attributes: end_params)
    case ending.call
    when :saved
      redirect_to employee_path(@employee, tab: "employment"), notice: ended_message
    when :conflict
      @latest = ending.latest
      @scheduled = scheduled_revisions
      render :new, status: :conflict
    else
      @scheduled = ending.blocking_revisions.presence || scheduled_revisions
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    undo = Employment::UndoEnd.new(@employee, by: Current.user, lock_version: params[:lock_version])
    case undo.call
    when :saved
      redirect_to employee_path(@employee), notice: "The exit was undone. #{@employee.full_name} is active again."
    else
      conflict = undo.latest.present?
      @employee.reload
      load_employee_page
      flash.now[:alert] = if conflict
        "#{undo.latest.updated_by&.full_name || 'Someone else'} changed this employee meanwhile. Check the details below, then try again."
      else
        "The exit can't be undone: #{undo.employee.errors.full_messages.to_sentence}."
      end
      render "employees/show", status: conflict ? :conflict : :unprocessable_content
    end
  end

  private

  def end_params
    params.expect(employee: %i[employment_end_date exit_reason exit_notes lock_version])
  end

  def scheduled_revisions = @employee.salary_revisions.in_force.where(effective_on: Date.current.next_day..).order(:effective_on)

  def refuse_if_exit_recorded
    return unless @employee.employment_end_date_in_database
    redirect_to employee_path(@employee), alert: "An exit is already recorded. Undo it first to change it."
  end

  def ended_message
    date = @employee.employment_end_date.to_fs(:human)
    if @employee.exited?
      "#{@employee.full_name}'s exit was recorded. Their last working day was #{date}, and their record is now read-only."
    else
      "#{@employee.full_name} is leaving. Their last working day is #{date}."
    end
  end
end
