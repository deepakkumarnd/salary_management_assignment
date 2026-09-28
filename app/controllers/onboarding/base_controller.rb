module Onboarding
  class BaseController < AuthenticatedController
    skip_before_action :require_organization_setup
    before_action :close_wizard_once_setup_is_complete

    helper_method :wizard, :onboarding_step_path

    private

    def wizard = @wizard ||= Wizard.new(Current.organization)

    def onboarding_step_path(step)
      case step
      when :organization then edit_onboarding_organization_path
      when :countries    then edit_onboarding_countries_path
      when :allowances   then edit_onboarding_allowances_path
      when :catalogue    then edit_onboarding_catalogue_path
      when :finish       then onboarding_root_path
      end
    end

    def close_wizard_once_setup_is_complete
      return unless Current.organization.setup_completed?
      redirect_to authenticated_root_path, notice: "Setup is already complete."
    end
  end
end
