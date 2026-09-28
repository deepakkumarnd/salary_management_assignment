module Onboarding
  class CountriesController < BaseController
    def edit
      @organization = Current.organization
      @selected_ids = @organization.country_ids
    end

    def update
      @organization = Current.organization
      country_ids = params.fetch(:organization, {}).permit(country_ids: [])[:country_ids]

      if @organization.update_operating_countries(country_ids)
        redirect_to edit_onboarding_allowances_path
      else
        @selected_ids = Array(country_ids).compact_blank.map(&:to_i)
        render :edit, status: :unprocessable_content
      end
    end
  end
end
