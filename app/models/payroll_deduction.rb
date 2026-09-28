# A deduction for one employee in one pay month: unpaid leave (days, in half-day steps) or another deduction (amount +
# description, e.g. "Salary advance recovery"). Monthly inputs, so editable and deletable, with optimistic locking.
# Deductions can be added, changed or deleted for last month, the current month and next month, so HR can make late
# adjustments and enter known ones early. Older and later months are read-only. Allowed for an exited employee's
# employed months within that window. (Changing a month after it was exported shows up as a warning on re-export.)
class PayrollDeduction < ApplicationRecord
  include SameOrganization
  include TracksUpdatedBy
  include WholeAmountAttribute

  KINDS = %w[unpaid_leave other].freeze

  belongs_to :organization
  belongs_to :employee
  belongs_to :created_by, class_name: "User"

  scope :unpaid_leave, -> { where(kind: "unpaid_leave") }
  scope :other, -> { where(kind: "other") }

  normalizes :description, with: ->(text) { text.squish.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :period_start, presence: true
  validates :description, presence: true, length: { maximum: 200 }, if: :other?
  validates_same_organization :employee
  validate :unpaid_days_valid, if: :unpaid_leave?
  validate :within_employment, :one_unpaid_leave_per_month
  validate :in_open_month
  before_destroy :refuse_unless_open_month

  whole_amount_attribute :amount, if: :other?

  def unpaid_leave? = kind == "unpaid_leave"
  def other? = kind == "other"

  def month = Payroll::Month.containing(period_start)

  # The months whose deductions can be changed: last month, the current month and next month.
  def self.open_months(today = Date.current)
    current = Payroll::Month.containing(today)
    [ current.previous, current, current.next ]
  end

  def self.open_months_label = open_months.map(&:label).to_sentence(last_word_connector: " or ")

  def changeable? = stored_month.in?(self.class.open_months)

  # Always the first day of the month.
  def period_start=(date)
    date = date.is_a?(String) ? (Payroll::Month.parse(date)&.start || Date.parse(date)) : date
    super(date&.beginning_of_month)
  rescue Date::Error
    super(nil)
  end

  # Days, as entered on forms: "1.5"
  def unpaid_days
    return @unpaid_days_input if defined?(@unpaid_days_input)
    format("%.1f", unpaid_half_days / 2.0) if unpaid_half_days
  end

  after_save :forget_unpaid_days_input

  def reload(...)
    forget_unpaid_days_input
    super
  end

  def unpaid_days=(value)
    @unpaid_days_input = value
    text = value.to_s.strip
    self.unpaid_half_days = text.match?(/\A\d+(\.[05]0?)?\z/) ? (BigDecimal(text) * 2).to_i : nil
  end

  private

  def forget_unpaid_days_input
    remove_instance_variable(:@unpaid_days_input) if defined?(@unpaid_days_input)
  end

  def unpaid_days_valid
    if unpaid_half_days.nil?
      errors.add(:unpaid_days, @unpaid_days_input.blank? ? :blank : "must be in half-day steps, e.g. 1 or 1.5")
    elsif unpaid_half_days <= 0
      errors.add(:unpaid_days, "must be more than 0")
    elsif employee && period_start && unpaid_half_days > 2 * month.days_employed(employee)
      errors.add(:unpaid_days, "can't be more than the #{month.days_employed(employee)} days employed in #{month.label}")
    end
  end

  # The month as saved (an update can't move an entry out of, or into, a closed month).
  def stored_month = persisted? ? Payroll::Month.containing(period_start_in_database) : month

  def in_open_month
    return if period_start.nil?
    return if [ month, stored_month ].all? { it.in?(self.class.open_months) }
    errors.add(:period_start, "can only be changed for #{self.class.open_months_label}")
  end

  def refuse_unless_open_month
    return if changeable?
    errors.add(:base, "#{stored_month.label} is closed: deductions can only be changed for #{self.class.open_months_label}")
    throw :abort
  end

  def within_employment
    return if employee.nil? || period_start.nil? || month.employed_range(employee)
    errors.add(:period_start, "must be a month in which the employee was employed")
  end

  def one_unpaid_leave_per_month
    return unless unpaid_leave? && employee && period_start
    return unless PayrollDeduction.unpaid_leave.where(employee:, period_start:).where.not(id:).exists?
    errors.add(:base, "Unpaid leave is already recorded for #{month.label}: change that entry instead")
  end
end
