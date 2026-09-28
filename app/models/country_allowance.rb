# An allowance paid to every employee of the organization in a country, as a % of basic (e.g. HRA 40% in India).
class CountryAllowance < ApplicationRecord
  include PercentAttribute
  include TracksUpdatedBy

  belongs_to :organization
  belongs_to :country

  normalizes :name, with: ->(name) { name.strip }

  percent_attribute :percent, column: :percent_bp, range: 1..20_000

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: %i[organization_id country_id], case_sensitive: false }
  validate :country_is_operating_country

  private

  def country_is_operating_country
    return if organization.nil? || country.nil? || organization.countries.include?(country)
    errors.add(:country, "is not one of the organization's operating countries")
  end
end
