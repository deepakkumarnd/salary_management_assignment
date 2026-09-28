# Records who last changed the record, so an edit conflict can say who changed it.
module TracksUpdatedBy
  extend ActiveSupport::Concern

  included do
    belongs_to :updated_by, class_name: "User", optional: true

    before_save { self.updated_by = Current.user if Current.user && has_changes_to_save? }
  end
end
