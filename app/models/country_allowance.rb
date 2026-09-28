# An allowance paid to every employee of the organization in a country, as a % of basic (e.g. HRA 40% in India).
class CountryAllowance < ApplicationRecord
  include BumpsPayDataVersion
  include OperatingCountry
  include PercentAttribute
  include TracksUpdatedBy

  belongs_to :organization
  belongs_to :country

  normalizes :name, with: ->(name) { name.strip }

  percent_attribute :percent, column: :percent_bp, range: 1..20_000

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: %i[organization_id country_id], case_sensitive: false }
  validate :name_not_used_by_a_role_allowance

  private

  def name_not_used_by_a_role_allowance
    conflict = AllowanceNameGuard.conflict_for_country_allowance(self)
    errors.add(:name, conflict) if conflict
  end
end
