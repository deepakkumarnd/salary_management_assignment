class Organization < ApplicationRecord
  CODE_PREFIX_FORMAT = /\A[A-Z]{2,6}\z/

  has_many :users, dependent: :restrict_with_error
  has_many :organization_countries, dependent: :destroy
  has_many :countries, through: :organization_countries
  has_many :departments
  has_many :job_roles
  has_many :country_allowances
  has_many :pay_structures
  has_many :employees
  has_many :salary_revisions
  has_many :payroll_deductions
  has_many :payroll_exports
  has_many :employee_imports

  accepts_nested_attributes_for :country_allowances, allow_destroy: true, reject_if: :blank_allowance_row?

  normalizes :name, with: ->(name) { name.strip }
  normalizes :employee_code_prefix, with: ->(prefix) { prefix.strip.upcase }

  before_validation :suggest_code_prefix, if: -> { employee_code_prefix.blank? }

  validates :name, presence: true, length: { maximum: 100 }
  validates :employee_code_prefix, format: { with: CODE_PREFIX_FORMAT, message: "must be 2 to 6 letters, A to Z" }
  validates :standard_hours_per_week, numericality: { only_integer: true, in: 1..80 }
  validate :allowance_names_unique_within_submission

  # "Acme Corp" → "ACME"; "X Ray Labs" → "XRL"; nil when nothing sensible can be derived.
  def self.suggested_code_prefix(name)
    words = name.to_s.upcase.scan(/[A-Z]+/)
    candidate = words.first.to_s.length >= 2 ? words.first : words.map { it[0] }.join
    candidate[0, 6] if candidate.length >= 2
  end

  def setup_completed? = setup_completed_at.present?

  # See BumpsPayDataVersion. An atomic increment, so concurrent changes never lose a bump.
  def self.bump_pay_data_version(id)
    where(id:).update_all("pay_data_version = pay_data_version + 1")
  end

  # Replaces the operating countries with the chosen ones. A country can't be dropped while something in the
  # organization still uses it; then nothing changes and the reason is in #errors.
  def update_operating_countries(country_ids)
    errors.clear
    chosen_ids = Country.where(id: Array(country_ids).compact_blank).ids
    if chosen_ids.empty?
      errors.add(:countries, "choose at least one country")
      return false
    end

    transaction do
      organization_countries.includes(:country).where.not(country_id: chosen_ids).each do |operating|
        next if operating.destroy
        errors.add(:base, "#{operating.country.name} can't be removed while it has allowances or pay structures")
      end
      raise ActiveRecord::Rollback if errors.any?

      (chosen_ids - organization_countries.pluck(:country_id)).each { organization_countries.create!(country_id: it) }
    end
    organization_countries.reset
    countries.reset
    errors.empty?
  end

  private

  def suggest_code_prefix
    self.employee_code_prefix = self.class.suggested_code_prefix(name)
  end

  def blank_allowance_row?(attributes)
    attributes.values_at("id", "name", "percent").all?(&:blank?)
  end

  # The unique index would reject these anyway; catching them here gives a message instead of an exception.
  def allowance_names_unique_within_submission
    country_allowances.target.reject(&:marked_for_destruction?)
      .group_by { [ it.country_id, it.name.to_s.downcase ] }
      .each do |(_, name), rows|
        next if name.blank? || rows.size < 2
        errors.add(:base, "#{rows.first.name} is listed more than once for #{rows.first.country&.name}")
      end
  end
end
