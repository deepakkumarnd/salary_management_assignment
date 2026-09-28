# Supported countries and their currency. Global reference data shared by all organizations.
class Country < ApplicationRecord
  has_many :organization_countries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  # The currency is part of every report in this country, for every organization.
  # (A new country has no data in any organization yet, so only updates invalidate.)
  after_update { Organization.update_all("pay_data_version = pay_data_version + 1") if saved_changes? }

  validates :currency_code, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO 4217 code" }
end
