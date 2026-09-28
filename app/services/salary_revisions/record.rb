module SalaryRevisions
  # Records a change of basic pay from an effective date: backdated, today or scheduled.
  #
  #   recording = SalaryRevisions::Record.new(employee, by: Current.user, attributes: params)
  #   recording.call   # → :saved or :invalid (errors on recording.revision)
  class Record
    attr_reader :revision

    def initialize(employee, by:, attributes:)
      @employee = employee
      @revision = employee.salary_revisions.build(organization: employee.organization, created_by: by)
      @revision.assign_attributes(attributes.to_h.symbolize_keys.slice(:effective_on, :basic_pay, :reason, :notes))
    end

    def call
      if @employee.exited?
        revision.errors.add(:base, "#{@employee.full_name} has left, so their pay can't be changed")
      elsif revision.hire?
        revision.errors.add(:reason, "can't be hire: the hire revision is created with the employee")
      end
      return :invalid if revision.errors.any? || !revision.valid?

      revision.save!(validate: false)
      :saved
    rescue ActiveRecord::RecordNotUnique
      # Another user recorded one for the same day between the check and the insert.
      revision.errors.add(:effective_on, SalaryRevision.duplicate_date_message(revision.effective_on))
      :invalid
    end
  end
end
