class JobRole < ApplicationRecord
  belongs_to :organization

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :organization_id, case_sensitive: false }
end
