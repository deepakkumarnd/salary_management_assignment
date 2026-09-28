# One basic-pay value for an employee from its effective date onwards. Append-only: a mistake is voided (and usually
# replaced through SalaryRevisions::Correct), never edited or deleted, so every past payment can be explained.
class SalaryRevision < ApplicationRecord
  include BumpsPayDataVersion
  include SameOrganization
  include WholeAmountAttribute

  REASONS = %w[hire appraisal promotion market_adjustment correction].freeze
  VOID_FIELDS = %w[voided_at voided_by_id void_reason updated_at].freeze

  belongs_to :organization
  belongs_to :employee
  belongs_to :created_by, class_name: "User"
  belongs_to :voided_by, class_name: "User", optional: true

  scope :in_force, -> { where(voided_at: nil) }

  normalizes :notes, :void_reason, with: ->(text) { text.strip.presence }

  whole_amount_attribute :basic_pay
  validates :effective_on, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates_same_organization :employee
  validate :within_employment, :hire_revision_on_hire_date, :one_in_force_per_day

  before_update { raise ActiveRecord::ReadOnlyRecord, "salary revisions can only be voided" if (changed - VOID_FIELDS).any? }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "salary revisions are never deleted" }

  # Correlated subquery for "basic pay as of date"; it uses the partial unique index (employee_id, effective_on).
  def self.basic_pay_as_of_sql(date)
    sanitize_sql_array([ <<~SQL.squish, date ])
      (SELECT r.basic_pay FROM salary_revisions r
        WHERE r.employee_id = employees.id AND r.voided_at IS NULL AND r.effective_on <= ?
        ORDER BY r.effective_on DESC LIMIT 1) AS basic_pay
    SQL
  end

  def self.duplicate_date_message(date) = "a revision already exists for #{date.to_fs(:human)}: void or correct it instead"

  def hire? = reason == "hire"
  def voided? = voided_at.present?
  def scheduled?(today = Date.current) = effective_on > today

  # Entered after the month it takes effect in began, so payroll owes (or recovers) arrears for earlier months.
  def backdated? = effective_on < (created_at || Time.current).to_date.beginning_of_month

  private

  def within_employment
    return if employee.nil? || effective_on.nil? || employee.hire_date.nil?

    if effective_on < employee.hire_date
      errors.add(:effective_on, "can't be before the hire date (#{employee.hire_date.to_fs(:human)})")
    elsif employee.employment_end_date && effective_on > employee.employment_end_date
      errors.add(:effective_on, "can't be after the last working day (#{employee.employment_end_date.to_fs(:human)})")
    end
  end

  def hire_revision_on_hire_date
    return unless hire? && employee && effective_on && effective_on != employee.hire_date
    errors.add(:effective_on, "must be the hire date for a hire revision")
  end

  # The partial unique index is the guarantee; this gives the same answer as a message instead of an exception.
  def one_in_force_per_day
    return unless new_record? && !voided? && employee&.persisted? && effective_on
    return unless SalaryRevision.in_force.exists?(employee_id: employee.id, effective_on:)
    errors.add(:effective_on, self.class.duplicate_date_message(effective_on))
  end
end
