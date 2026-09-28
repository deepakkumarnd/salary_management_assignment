# For records that belong to an organization and a country: the country must be one the organization operates in.
module OperatingCountry
  extend ActiveSupport::Concern

  included do
    validate :country_is_operating_country
  end

  private

  def country_is_operating_country
    return if organization.nil? || country.nil? || organization.countries.include?(country)
    errors.add(:country, "is not one of the organization's operating countries")
  end
end
