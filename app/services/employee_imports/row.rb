module EmployeeImports
  # One data row of an employee CSV. Normalises the values the way Employee does and checks everything that needs no
  # database: the same rules and messages as Employee (spec/services/employee_imports/row_spec.rb keeps them in step).
  # EmployeeImports::Run adds the checks that do (email already used, country, pay structure) to #errors.
  class Row
    include ActiveModel::Model
    include ActiveModel::Attributes
    include WholeAmountAttribute

    COLUMNS = %w[name email department designation basic_pay country hire_date employment_type].freeze
    REQUIRED_COLUMNS = %w[name email department designation basic_pay country].freeze
    NAME_LIMIT = 60   # departments and job roles

    attribute :row_number, :integer
    attribute :data                                    # the row's known columns, as uploaded
    attribute :name
    attribute :email
    attribute :department
    attribute :designation
    attribute :basic_pay
    attribute :country
    attribute :hire_date_text
    attribute :employment_type
    attribute :today, :date

    # Set by EmployeeImports::Run once the row passes every check.
    attr_accessor :country_id, :department_id, :job_role_id

    # In column order, so the reasons read like the row.
    validates :name, presence: true, length: { maximum: 100 }
    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :department, :designation, presence: true, length: { maximum: NAME_LIMIT }
    whole_amount_attribute :basic_pay                  # "12,00,000" → 1200000
    validates :country, presence: true
    validate :hire_date_valid
    validates :employment_type, inclusion: { in: Employee.employment_types.values,
                                             message: "must be full_time, part_time or contractor" }

    def self.from_csv(fields, row_number:, today:)
      data = COLUMNS.to_h { [ it, fields[it].to_s.strip ] }
      new(row_number:, data:, today:,
          name: data["name"].squish, email: data["email"].downcase, department: data["department"].squish,
          designation: data["designation"].squish, country: data["country"].squish, basic_pay: data["basic_pay"],
          hire_date_text: data["hire_date"],
          employment_type: data["employment_type"].downcase.gsub(/[\s-]+/, "_").presence || "full_time")
    end

    def self.human_attribute_name(attribute, options = {})
      attribute.to_s == "hire_date_text" ? "Hire date" : super
    end

    # Blank means the import date.
    def hire_date
      return today if hire_date_text.blank?
      Date.strptime(hire_date_text, "%Y-%m-%d") if hire_date_text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    rescue Date::Error
      nil
    end

    def importable? = errors.empty?

    private

    def hire_date_valid
      date = hire_date
      if date.nil?
        errors.add(:hire_date_text, "must be a date written as YYYY-MM-DD, like #{today.iso8601}")
      elsif date > today
        errors.add(:hire_date_text, "can't be in the future")
      end
    end
  end
end
