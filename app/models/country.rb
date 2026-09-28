# Supported countries and their currency. Global reference data shared by all organizations.
class Country < ApplicationRecord
  has_many :organization_countries, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :currency_code, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter ISO 4217 code" }
end
