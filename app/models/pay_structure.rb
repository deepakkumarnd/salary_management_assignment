# How one job role is paid in one country: default basic pay (pre-fills new hires), role allowances on top of the
# country's, a target variable pay (% of gross) and an overtime rate (% of hourly basic).
class PayStructure < ApplicationRecord
  include OperatingCountry
  include PercentAttribute
  include TracksUpdatedBy
  include WholeAmountAttribute

  belongs_to :organization
  belongs_to :country
  belongs_to :job_role

  has_many :allowances, class_name: "PayStructureAllowance", inverse_of: :pay_structure, dependent: :destroy
  accepts_nested_attributes_for :allowances, allow_destroy: true, reject_if: :blank_allowance_row?

  attr_readonly :country_id, :job_role_id

  whole_amount_attribute :default_basic_pay
  percent_attribute :variable_pay_percent, column: :variable_pay_percent_bp, range: 0..20_000
  percent_attribute :overtime_percent, column: :overtime_percent_bp, range: 0..40_000

  validate :one_per_country_and_role, :job_role_in_same_organization, :allowance_names_unique_within_submission

  # An allowance-only change must still bump lock_version, so a concurrent edit to the structure or its allowances
  # is detected. Runs first so TracksUpdatedBy sees the change too.
  before_save :record_allowance_changes, prepend: true

  # The pay breakdown for a basic pay under this structure: the country's allowances, then the role's.
  def breakdown_for(basic_pay, country_allowances: organization.country_allowances.where(country_id:))
    PayCalculator.new(
      basic_pay:,
      allowances: country_allowances.map { { name: it.name, percent_bp: it.percent_bp, source: :country } } +
                  allowances.reject(&:marked_for_destruction?)
                            .map { { name: it.name, percent_bp: it.percent_bp, source: :role } },
      variable_pay_percent_bp:, overtime_percent_bp:,
      standard_hours_per_week: organization.standard_hours_per_week
    ).breakdown
  end

  private

  def blank_allowance_row?(attributes)
    attributes.values_at("id", "name", "percent").all?(&:blank?)
  end

  def one_per_country_and_role
    return if country.nil? || job_role.nil?
    duplicates = PayStructure.where(country_id:, job_role_id:).where.not(id:)
    errors.add(:job_role, "already has a pay structure in #{country.name}") if duplicates.exists?
  end

  def job_role_in_same_organization
    return if job_role.nil? || job_role.organization_id == organization_id
    errors.add(:job_role, "must belong to the same organization")
  end

  def allowance_names_unique_within_submission
    allowances.reject(&:marked_for_destruction?).group_by { it.name.to_s.downcase }.each do |name, rows|
      errors.add(:base, "#{rows.first.name} is listed more than once") if name.present? && rows.size > 1
    end
  end

  def record_allowance_changes
    self.updated_at = Time.current if persisted? && allowances.target.any?(&:changed_for_autosave?)
  end
end
