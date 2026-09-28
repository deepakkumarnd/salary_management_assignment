# Base class for every page of the app: signed in, scoped to the user's organization, and set up.
class AuthenticatedController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :require_organization_setup

  private

  def set_current_tenant
    Current.user = current_user
    Current.organization = current_user.organization
  end

  def require_organization_setup
    redirect_to onboarding_root_path unless Current.organization.setup_completed?
  end
end
