class PayStructuresController < AuthenticatedController
  ALLOWANCE_ATTRIBUTES = [ [ :id, :name, :percent, :_destroy ] ].freeze

  before_action :set_structure, only: %i[edit update destroy]

  def new
    @country = Current.organization.countries.find(params[:country_id])
    @structure = Current.organization.pay_structures.build(country: @country, overtime_percent_bp: 15_000)
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
