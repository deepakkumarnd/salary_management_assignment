# Deductions for a pay month: the per-country month page (index) lists the roster with an unpaid-days input and other
# deductions per row; the same row appears on the employee page's Deductions tab. Changes answer with a Turbo Stream
# that replaces the row (and the month's totals), so a month's leave can be entered in one sitting.
class PayrollDeductionsController < AuthenticatedController
  include Pagy::Method

  PER_PAGE = 50   # a data-entry page: long enough to enter a month's leave with few page turns

  before_action :set_deduction, only: %i[update destroy]

  def index
    if request.path == deductions_path   # /deductions, or the filter form: move to the month's own URL
      month = Payroll::Month.parse(params[:month]) || Payroll::Month.containing(Date.current)
      return redirect_to(month_deductions_path(month.to_param, { country_id: params[:country_id].presence || default_country&.id,
                                                                 q: params[:q].presence }.compact))
    end

    @month = Payroll::Month.parse(params[:month]) or raise ActiveRecord::RecordNotFound
    @countries = Current.organization.countries.order(:name)
    @country = params[:country_id].present? ? @countries.find(params[:country_id]) : @countries.first
    @q = params[:q].to_s.strip.presence
    @pagy, @employees = pagy(:offset, roster, limit: PER_PAGE, page: [ params[:page].to_i, 1 ].max)
    @deductions = PayrollDeduction.where(employee_id: @employees.map(&:id), period_start: @month.start).order(:id).to_a
                                  .group_by(&:employee_id)
  end

  def create
    @employee = Current.organization.employees.find_by!(employee_code: deduction_params[:employee_id])
    @month = Payroll::Month.parse(deduction_params[:month]) or raise ActiveRecord::RecordNotFound
    @deduction = Current.organization.payroll_deductions.build(
      employee: @employee, period_start: @month.start, created_by: Current.user,
      **deduction_params.slice(:kind, :unpaid_days, :amount, :description).to_h.symbolize_keys
    )
    respond_with_row(@deduction.save ? :ok : :unprocessable_content)
  end

  def update
    return destroy if @deduction.unpaid_leave? && deduction_params[:unpaid_days].to_s.strip.in?([ "", "0" ])

    status = update_with_lock(@deduction, deduction_params.slice(:unpaid_days, :amount, :description, :lock_version))
    @conflict = "#{@latest.updated_by&.full_name || 'Someone else'} changed this deduction meanwhile; its saved value is shown." if status == :conflict
    @deduction.reload if status == :conflict
    respond_with_row({ saved: :ok, conflict: :conflict }.fetch(status, :unprocessable_content))
  end

  def destroy
    return respond_with_row(:unprocessable_content) unless @deduction.destroy

    @deduction = nil
    respond_with_row(:ok)
  end

  private

  def set_deduction
    @deduction = Current.organization.payroll_deductions.find(params[:id])
    @employee = @deduction.employee
    @month = @deduction.month
  end

  def deduction_params
    params.expect(payroll_deduction: %i[employee_id month kind unpaid_days amount description lock_version])
  end

  def default_country = Current.organization.countries.order(:name).first

  def roster
    scope = Payroll::Roster.employees(Current.organization, @country, @month).includes(:country).order(:employee_code)
    return scope unless @q

    term = "%#{Employee.sanitize_sql_like(@q)}%"
    scope.where("employees.full_name LIKE :term ESCAPE '\\' OR employees.employee_code LIKE :term ESCAPE '\\'", term:)
  end

  # Re-renders the employee's row for the month (with this deduction's errors, if any) and the month's totals.
  def respond_with_row(status)
    respond_to do |format|
      format.turbo_stream do
        deductions = @employee.payroll_deductions.where(period_start: @month.start).order(:id).to_a
        render status:, turbo_stream: [
          turbo_stream.replace(helpers.deduction_row_id(@employee, @month),
                               partial: "payroll_deductions/row",
                               locals: { employee: @employee, month: @month, deductions:, failed: (@deduction if status != :ok),
                                         notice: @conflict, label: params[:row_label].presence&.to_sym || :employee }),
          turbo_stream.replace(helpers.deduction_totals_id(@employee.country_id, @month),
                               partial: "payroll_deductions/totals",
                               locals: { country_id: @employee.country_id, month: @month,
                                         deductions: PayrollDeduction.where(employee: Payroll::Roster.employees(Current.organization, @employee.country, @month),
                                                                            period_start: @month.start) })
        ]
      end
      format.html do
        flash[:alert] = @deduction.errors.full_messages.to_sentence if status != :ok && @deduction&.errors&.any?
        redirect_to month_deductions_path(@month.to_param, country_id: @employee.country_id)
      end
    end
  end
end
