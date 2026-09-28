module Onboarding
  class AllowancesController < BaseController
    before_action :require_countries

    def edit
      @organization = Current.organization
    end

    # Nested attributes are resolved through Current.organization.country_allowances, so another organization's
    # allowance id raises RecordNotFound (404).
    def update
      @organization = Current.organization
      return add_row if params[:add_allowance].present?

      if @organization.update(allowance_params)
        redirect_to edit_onboarding_catalogue_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    # "+ Add allowance" without JavaScript: show the form again, keeping what was typed, with one more empty row
    # for that country. Nothing is saved.
    def add_row
      @organization.assign_attributes(allowance_params)
      @add_row_for = params[:add_allowance].to_i
      render :edit
    end

    def allowance_params
      params.fetch(:organization, {}).permit(country_allowances_attributes: %i[id country_id name percent _destroy])
    end

    def require_countries
      return if wizard.available?(:allowances)
      redirect_to edit_onboarding_countries_path, alert: "Choose your countries first."
    end
  end
end
