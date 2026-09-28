# An allowance for one country + role only, on top of the country's allowances (e.g. Special 15% for engineers).
class PayStructureAllowance < ApplicationRecord
  include PercentAttribute

  belongs_to :pay_structure, inverse_of: :allowances

  normalizes :name, with: ->(name) { name.strip }

  percent_attribute :percent, column: :percent_bp, range: 1..20_000

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :pay_structure_id, case_sensitive: false }
  validate :name_not_used_by_a_country_allowance

  private

  def name_not_used_by_a_country_allowance
    conflict = AllowanceNameGuard.conflict_for_role_allowance(self)
    errors.add(:name, conflict) if conflict
  end
end
