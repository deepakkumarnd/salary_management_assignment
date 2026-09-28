class JobRole < ApplicationRecord
  belongs_to :organization
  has_many :pay_structures, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id, case_sensitive: false }
end
