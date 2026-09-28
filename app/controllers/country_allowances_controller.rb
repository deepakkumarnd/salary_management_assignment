class CountryAllowancesController < AuthenticatedController
  before_action :set_country
  before_action :set_allowance, only: %i[edit update destroy]

  def new
    @allowance = allowances.build
  end

  def create
    @allowance = allowances.build(allowance_params.except(:lock_version))
    if @allowance.save
      redirect_to country_path(@country), notice: "#{@allowance.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    case update_with_lock(@allowance, allowance_params)
    when :saved    then redirect_to country_path(@country), notice: "#{@allowance.name} was updated."
    when :conflict then render :edit, status: :conflict
    else render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @allowance.destroy!
    redirect_to country_path(@country), notice: "#{@allowance.name} was deleted."
  end

  private

  def set_country
    @country = Current.organization.countries.find(params[:country_id])
  end

  def allowances = Current.organization.country_allowances.where(country: @country)

  def set_allowance
    @allowance = allowances.find(params[:id])
  end

  def allowance_params
    params.expect(country_allowance: %i[name percent lock_version])
  end
end
