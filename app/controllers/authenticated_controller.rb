# Base class for every page of the app: signed in, scoped to the user's organization, and set up.
class AuthenticatedController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :require_organization_setup

  private

  # Saves with Rails' optimistic locking (the form sends the lock_version it was based on). Returns :saved, :invalid
  # or :conflict. On a conflict, @latest holds what was saved in the meantime, and the record keeps the user's edits
  # with the fresh lock_version, so saving again re-applies them knowingly.
  def update_with_lock(record, attributes)
    record.update(attributes) ? :saved : :invalid
  rescue ActiveRecord::StaleObjectError
    @latest = record.class.find(record.id)
    record.lock_version = @latest.lock_version
    :conflict
  end

  def set_current_tenant
    Current.user = current_user
    Current.organization = current_user.organization
  end

  def require_organization_setup
    redirect_to onboarding_root_path unless Current.organization.setup_completed?
  end
end
