module SalaryRevisions
  # Replaces a wrong revision: voids it and records the right one in one transaction, so a failed replacement leaves
  # the original in force. The replacement defaults to the original's date, amount and reason. A hire revision keeps
  # its hire date and reason (the hire date itself is changed by editing the employee).
  #
  #   correction = SalaryRevisions::Correct.new(revision, by: Current.user, void_reason: "Typo", attributes: params)
  #   correction.call   # → :saved, :invalid (errors on correction / correction.replacement) or :conflict
  class Correct
    include ActiveModel::Validations

    attr_reader :original, :replacement, :void_reason

    validates :void_reason, presence: true

    def initialize(original, by:, void_reason: nil, attributes: {})
      @original = original
      @user = by
      @void_reason = void_reason.to_s.strip.presence
      @replacement = original.employee.salary_revisions.build(
        organization: original.organization, created_by: by,
        effective_on: original.effective_on, basic_pay: original.basic_pay, reason: original.reason
      )
      @replacement.assign_attributes(attributes.to_h.symbolize_keys.slice(:effective_on, :basic_pay, :reason, :notes))
      @replacement.assign_attributes(effective_on: original.effective_on, reason: "hire") if original.hire?
    end

    def call
      return :conflict if original.voided?

      valid?
      if original.employee.exited?
        errors.add(:base, "#{original.employee.full_name} has left, so their pay history can't be changed")
      elsif !original.hire? && replacement.hire?
        replacement.errors.add(:reason, "can't be hire: only the hire revision is a hire")
      end
      return :invalid if errors.any? || replacement.errors.any?

      SalaryRevision.transaction do
        raise Conflict unless Void.void!(original, by: @user, reason: void_reason)
        raise ActiveRecord::Rollback unless replacement.save
      end
      original.reload
      replacement.persisted? ? :saved : :invalid
    rescue Conflict
      original.reload
      :conflict
    rescue ActiveRecord::RecordNotUnique
      replacement.errors.add(:effective_on, SalaryRevision.duplicate_date_message(replacement.effective_on))
      :invalid
    end

    class Conflict < StandardError; end
  end
end
