# Per-request context, set by AuthenticatedController.
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :organization
end
