class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  protected

  def after_sign_in_path_for(user)
    stored_location_for(user) ||
      (user.organization.setup_completed? ? authenticated_root_path : onboarding_root_path)
  end
end
