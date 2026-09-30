class PayStructuresController < AuthenticatedController
  ALLOWANCE_ATTRIBUTES = [ [ :id, :name, :percent, :_destroy ] ].freeze

  before_action :set_structure, only: %i[edit update destroy]

  # The live pay breakdown in the employee and salary-revision forms (a Turbo Frame; the calculation never runs in
  # JavaScript). Either country_id + job_role_id + basic_pay (new employee), or employee_id + basic_pay + effective_on
  # (salary revision, which also compares with the basic in force on that date).
  def preview
    if params[:employee_id].present?
      @employee = Current.organization.employees.find_by!(employee_code: params[:employee_id])
      @structure = @employee.pay_structure
      @effective_on = Date.iso8601(params[:effective_on].to_s) rescue nil
      @basic_before = @employee.basic_pay_on(@effective_on) if @effective_on
    else
      @structure = Current.organization.pay_structures.find_by(country_id: params[:country_id], job_role_id: params[:job_role_id])
      @country = Current.organization.countries.find_by(id: params[:country_id])
      @job_role = Current.organization.job_roles.find_by(id: params[:job_role_id])
    end
    amount = params[:basic_pay].to_s.gsub(/[\s,_]/, "")
    @basic_pay = amount.to_i if amount.match?(/\A\d{1,12}\z/) && amount.to_i.positive?
    @breakdown = @structure.breakdown_for(@basic_pay) if @structure && @basic_pay

    render partial: "pay_structures/preview"
  end

  def new
    @country = Current.organization.countries.find(params[:country_id])
    job_role = Current.organization.job_roles.find_by(id: params[:job_role_id])   # preselected, e.g. from an import
    @structure = Current.organization.pay_structures.build(country: @country, job_role:, overtime_percent_bp: 15_000)
  end

  def create
    @structure = Current.organization.pay_structures.build(create_params)
    @country = Current.organization.countries.find(@structure.country_id)
    return add_allowance_row(:new) if params[:add_allowance].present?

    if @structure.save
      redirect_to country_path(@country), notice: "Pay structure for #{@structure.job_role.name} was saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    return add_allowance_row(:edit) if params[:add_allowance].present?

    case update_with_lock(@structure, update_params)
    when :saved    then redirect_to country_path(@country), notice: "Pay structure for #{@structure.job_role.name} was saved."
    when :conflict then render :edit, status: :conflict
    else render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @structure.destroy
      redirect_to country_path(@country), notice: "Pay structure for #{@structure.job_role.name} was deleted."
    else
      redirect_to country_path(@country), alert: @structure.errors.full_messages.to_sentence
    end
  end

  private

  def set_structure
    @structure = Current.organization.pay_structures.find(params[:id])
    @country = @structure.country
  end

  # Country and role are chosen once; editing changes the pay only.
  def create_params
    params.expect(pay_structure: [ :country_id, :job_role_id, :default_basic_pay, :variable_pay_percent,
                                   :overtime_percent, allowances_attributes: ALLOWANCE_ATTRIBUTES ])
  end

  def update_params
    params.expect(pay_structure: [ :default_basic_pay, :variable_pay_percent, :overtime_percent, :lock_version,
                                   allowances_attributes: ALLOWANCE_ATTRIBUTES ])
  end

  # "+ Add allowance" without JavaScript: show the form again with what was typed and one more empty row.
  def add_allowance_row(view)
    @structure.assign_attributes(update_params) if view == :edit   # create has already built it from the params
    @add_allowance_row = true
    render view
  end
end
