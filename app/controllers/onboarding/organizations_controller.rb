module Onboarding
  class OrganizationsController < BaseController
    def edit
      @organization = Current.organization
    end

    def update
      @organization = Current.organization
      if @organization.update(organization_params)
        redirect_to edit_onboarding_countries_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def organization_params
      params.expect(organization: %i[name employee_code_prefix standard_hours_per_week])
    end
  end
end
