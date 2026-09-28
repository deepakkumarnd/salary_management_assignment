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
      if @organization.update(allowance_params)
        redirect_to edit_onboarding_catalogue_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def allowance_params
      params.fetch(:organization, {}).permit(country_allowances_attributes: %i[id country_id name percent _destroy])
    end

    def require_countries
      return if wizard.available?(:allowances)
      redirect_to edit_onboarding_countries_path, alert: "Choose your countries first."
    end
  end
end
