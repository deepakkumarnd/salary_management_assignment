module Employment
  # Records a leaver: last working day, reason and notes. Past and future dates are both allowed (a future date means
  # the employee is Leaving until then). Refused while revisions in force take effect after the last working day.
  #
  #   ending = Employment::End.new(employee, by: Current.user, attributes: params)   # params include lock_version
  #   ending.call   # → :saved, :invalid (ending.blocking_revisions) or :conflict (ending.latest)
  class End
    attr_reader :employee, :latest, :blocking_revisions

    def initialize(employee, by:, attributes:)
      @employee = employee
      @user = by
      @attributes = attributes.to_h.symbolize_keys.slice(:employment_end_date, :exit_reason, :exit_notes, :lock_version)
      @blocking_revisions = []
    end

    def call
      if employee.employment_end_date_in_database
        employee.errors.add(:base, "An exit is already recorded. Undo it first to change it.")
        return :invalid
      end

      employee.assign_attributes(@attributes.merge(updated_by: @user))
      employee.validate
      %i[employment_end_date exit_reason].each do |attribute|
        employee.errors.add(attribute, :blank) if employee.public_send(attribute).nil? && employee.errors[attribute].none?
      end
      check_later_revisions
      return :invalid if employee.errors.any?

      employee.save!(validate: false)
      :saved
    rescue ActiveRecord::StaleObjectError
      @latest = Employee.find(employee.id)
      employee.lock_version = @latest.lock_version
      :conflict
    end

    private

    def check_later_revisions
      return if employee.employment_end_date.nil?

      @blocking_revisions = employee.salary_revisions.in_force.where(effective_on: employee.employment_end_date.next_day..)
                                    .order(:effective_on).to_a
      return if blocking_revisions.empty?

      dates = blocking_revisions.map { it.effective_on.to_fs(:human) }.to_sentence
      noun = blocking_revisions.one? ? "a salary revision that takes" : "salary revisions that take"
      employee.errors.add(:employment_end_date, "is before #{noun} effect on #{dates}: void #{blocking_revisions.one? ? 'it' : 'them'} first")
    end
  end
end
