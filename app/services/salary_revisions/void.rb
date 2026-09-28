module SalaryRevisions
  # Takes a wrong revision out of force, keeping it (struck through) with who voided it and why.
  #
  #   voiding = SalaryRevisions::Void.new(revision, by: Current.user, reason: "Wrong amount")
  #   voiding.call   # → :saved, :invalid, or :conflict when someone else voided it first (revision reloaded)
  class Void
    attr_reader :revision

    def initialize(revision, by:, reason:)
      @revision = revision
      @user = by
      @reason = reason
    end

    def call
      revision.void_reason = @reason
      if revision.void_reason.nil?
        revision.errors.add(:void_reason, :blank)
      elsif revision.hire?
        revision.errors.add(:base, "The hire revision can't be voided on its own. Correct it instead.")
      elsif revision.employee.exited?
        revision.errors.add(:base, "#{revision.employee.full_name} has left, so their pay history can't be changed")
      end
      return :invalid if revision.errors.any?

      self.class.void!(revision, by: @user, reason: revision.void_reason) ? :saved : conflict
    end

    # A conditional update, so two users can't both void the same revision: false when it was already voided.
    def self.void!(revision, by:, reason:)
      now = Time.current
      voided = SalaryRevision.where(id: revision.id, voided_at: nil)
                             .update_all(voided_at: now, voided_by_id: by.id, void_reason: reason, updated_at: now)
      Organization.bump_pay_data_version(revision.organization_id) if voided == 1   # update_all skips callbacks
      voided == 1
    end

    private

    def conflict
      revision.reload
      :conflict
    end
  end
end
