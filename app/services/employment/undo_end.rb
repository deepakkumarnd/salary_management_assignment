module Employment
  # Withdraws a recorded exit (e.g. a resignation is withdrawn), including for someone already exited. Refused when
  # another current employee now has the same email (e.g. they were already rehired as a new record).
  #
  #   undo = Employment::UndoEnd.new(employee, by: Current.user, lock_version: params[:lock_version])
  #   undo.call   # → :saved, :invalid (errors on undo.employee) or :conflict (undo.latest)
  class UndoEnd
    attr_reader :employee, :latest

    def initialize(employee, by:, lock_version:)
      @employee = employee
      @user = by
      @lock_version = lock_version
    end

    def call
      if employee.employment_end_date.nil?
        employee.errors.add(:base, "There is no exit to undo.")
        return :invalid
      end

      employee.assign_attributes(employment_end_date: nil, exit_reason: nil, exit_notes: nil, lock_version: @lock_version,
                                 updated_by: @user)
      employee.save ? :saved : :invalid
    rescue ActiveRecord::StaleObjectError
      @latest = Employee.find(employee.id)
      :conflict
    rescue ActiveRecord::RecordNotUnique
      employee.errors.add(:email, "is already used by a current employee")
      :invalid
    end
  end
end
