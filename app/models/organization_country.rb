# A country the organization operates in.
class OrganizationCountry < ApplicationRecord
  belongs_to :organization
  belongs_to :country

  has_many :country_allowances, primary_key: %i[organization_id country_id], foreign_key: %i[organization_id country_id],
                                dependent: :restrict_with_error

  validates :country_id, uniqueness: { scope: :organization_id }
end
