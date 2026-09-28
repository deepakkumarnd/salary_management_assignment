# Records that feed computed pay reports (insights) bump their organization's pay_data_version whenever they change.
# Cached reports include the version in their cache key, so any change makes them recompute.
#
# The bump runs inside the record's own transaction, so a rolled-back change doesn't invalidate anything. Bulk
# updates that skip callbacks (update_all, insert_all) must call Organization.bump_pay_data_version themselves.
module BumpsPayDataVersion
  extend ActiveSupport::Concern

  included do
    after_save :bump_pay_data_version, if: :saved_changes?
    after_destroy :bump_pay_data_version
  end

  private

  def bump_pay_data_version = Organization.bump_pay_data_version(pay_data_organization_id)

  # Override when the organization is reached through another record.
  def pay_data_organization_id = organization_id
end
