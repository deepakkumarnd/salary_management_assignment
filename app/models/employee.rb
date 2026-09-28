# A person's employment: identity, country (fixed), role, department, hire date and, once they leave, last working day
# and exit reason. Holds no pay amount itself: pay lives in salary revisions. Employees are never deleted.
class Employee < ApplicationRecord
  include BumpsPayDataVersion
  include OperatingCountry
  include SameOrganization
  include TracksUpdatedBy
  include WholeAmountAttribute

  EXIT_REASONS = %w[resignation termination retirement end_of_contract internal_transfer recorded_in_error other].freeze
  EXIT_FIELDS = %w[employment_end_date exit_reason exit_notes].freeze
  BOOKKEEPING_FIELDS = %w[lock_version updated_by_id updated_at].freeze

  belongs_to :organization
  belongs_to :country
  belongs_to :job_role
  belongs_to :department
  # Enforced by a composite foreign key; validated below with a clearer message than the association's own.
  belongs_to :pay_structure, foreign_key: %i[country_id job_role_id], primary_key: %i[country_id job_role_id],
                             optional: true
  has_many :salary_revisions, inverse_of: :employee, dependent: :restrict_with_error
  has_many :payroll_deductions, dependent: :restrict_with_error

  enum :employment_type, { full_time: "full_time", part_time: "part_time", contractor: "contractor" }, validate: true

  normalizes :full_name, with: ->(name) { name.squish }
  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :exit_reason, :exit_notes, with: ->(text) { text.strip.presence }

  attr_readonly :employee_code, :country_id                        # assigned once, never change
  attribute :initial_basic_pay, :integer                           # create only → becomes the hire revision
  attr_accessor :recorded_by                                       # author of the hire revision (default Current.user)

  whole_amount_attribute :initial_basic_pay, on: :create
  validates :full_name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :hire_date, presence: true
  validates :exit_reason, inclusion: { in: EXIT_REASONS }, allow_nil: true
  validates :exit_reason, presence: true, if: :employment_end_date?
  validates :employment_end_date, presence: true, if: :exit_reason?
  validates_same_organization :department, :job_role
  validate :email_unique_among_current_employees, :hire_date_not_in_future, :pay_structure_exists,
           :end_not_before_hire, :hire_date_before_other_revisions, :not_exited_when_editing
  validate :hire_revision_valid, on: :create

  before_create :assign_employee_code
  after_create :save_hire_revision
  before_update :correct_hire_revision, if: :hire_date_changed?

  # Employment status, always derived from dates (never stored)
  scope :employed_on, ->(date) {
    where(hire_date: ..date).where("employees.employment_end_date IS NULL OR employees.employment_end_date >= ?", date)
  }
  scope :employed_during, ->(from, to) {
    where(hire_date: ..to).where("employees.employment_end_date IS NULL OR employees.employment_end_date >= ?", from)
  }
  scope :countable, -> { where("employees.exit_reason IS NOT 'recorded_in_error'") }   # insights + exports
  scope :with_basic_pay_as_of, ->(date) { select("employees.*", SalaryRevision.basic_pay_as_of_sql(date)) }

  def to_param = employee_code                                     # /employees/ACME-00042

  def status(today = Date.current)
    return :active if employment_end_date.nil?
    employment_end_date >= today ? :leaving : :exited
  end

  def exited?(today = Date.current) = status(today) == :exited

  def basic_pay_on(date) = salary_revisions.in_force.where(effective_on: ..date).order(effective_on: :desc).pick(:basic_pay)

  # Today's pay, or the last working day's for someone who has left.
  def pay_date(today = Date.current) = [ today, employment_end_date ].compact.min

  def breakdown_on(date)
    basic_pay = basic_pay_on(date)
    pay_structure.breakdown_for(basic_pay) if basic_pay
  end

  # The next change in force after the date, e.g. a scheduled raise.
  def next_revision_after(date) = salary_revisions.in_force.where(effective_on: date.next_day..).order(:effective_on).first

  private

  def hire_revision_author = recorded_by || Current.user

  def assign_employee_code
    self.employee_code = EmployeeCode.next_for(organization)
  end

  def hire_revision
    @hire_revision ||= SalaryRevision.new(employee: self, reason: "hire")
  end

  def hire_revision_valid
    hire_revision.assign_attributes(organization:, effective_on: hire_date, basic_pay: initial_basic_pay,
                                    created_by: hire_revision_author)
    return if hire_revision.valid?

    # Basic pay is reported on initial_basic_pay, and dates on the employee's own fields.
    hire_revision.errors.each do |error|
      next if error.attribute.in?(%i[basic_pay effective_on employee organization])
      errors.add(:base, "Hire revision: #{error.full_message}")
    end
  end

  def save_hire_revision
    hire_revision.save!
  end

  # A new hire date moves the hire revision: void the old one and record the same basic on the new date.
  def correct_hire_revision
    old = salary_revisions.in_force.find_by!(reason: "hire")
    void_reason = "Hire date changed from #{hire_date_in_database.to_fs(:human)} to #{hire_date.to_fs(:human)}"
    SalaryRevision.where(id: old.id, voided_at: nil)
                  .update_all(voided_at: Time.current, voided_by_id: hire_revision_author.id, void_reason:,
                              updated_at: Time.current)
    Organization.bump_pay_data_version(organization_id)   # update_all skips callbacks
    SalaryRevision.create!(organization:, employee: self, reason: "hire", effective_on: hire_date,
                           basic_pay: old.basic_pay, notes: old.notes, created_by: hire_revision_author)
  end

  def email_unique_among_current_employees
    return if email.blank? || employment_end_date.present? || organization_id.nil?

    other = Employee.where(organization_id:, email:, employment_end_date: nil).where.not(id:).pick(:employee_code)
    errors.add(:email, "is already used by current employee #{other}") if other
  end

  def hire_date_not_in_future
    errors.add(:hire_date, "can't be in the future") if hire_date && hire_date > Date.current
  end

  def pay_structure_exists
    return if country.nil? || job_role.nil? || !(new_record? || job_role_id_changed?)
    return if PayStructure.exists?(country_id:, job_role_id:)
    errors.add(:job_role, "has no pay structure in #{country.name} yet. Create one in Pay policy first.")
  end

  def end_not_before_hire
    return if employment_end_date.nil? || hire_date.nil? || employment_end_date >= hire_date
    errors.add(:employment_end_date, "can't be before the hire date (#{hire_date.to_fs(:human)})")
  end

  def hire_date_before_other_revisions
    return unless persisted? && hire_date_changed? && hire_date

    first = salary_revisions.in_force.where.not(reason: "hire").order(:effective_on).first
    return if first.nil? || first.effective_on > hire_date
    errors.add(:hire_date, "must be before the salary revision on #{first.effective_on.to_fs(:human)}")
  end

  # Exited employees are read-only, apart from undoing the exit (Employment::UndoEnd).
  def not_exited_when_editing
    return unless persisted? && employment_end_date_in_database && employment_end_date_in_database < Date.current
    return if (changed - EXIT_FIELDS - BOOKKEEPING_FIELDS).empty?
    errors.add(:base, "Exited employees can't be changed. Undo the exit first.")
  end
end
