module Onboarding
  # Decides, from the organization's data rather than a stored step counter, which setup steps are complete and
  # where to resume. Several HR users can work through it, and it survives signing out.
  class Wizard
    STEPS = %i[organization countries allowances catalogue].freeze

    attr_reader :organization

    def initialize(organization)
      @organization = organization
    end

    def steps = STEPS

    def complete?(step)
      case step
      when :organization then organization.name_in_database.present? &&
                              organization.employee_code_prefix_in_database.to_s.match?(Organization::CODE_PREFIX_FORMAT)
      when :countries    then organization.organization_countries.exists?
      when :allowances   then true   # optional
      when :catalogue    then organization.departments.exists? && organization.job_roles.exists?
      else raise ArgumentError, "unknown step #{step.inspect}"
      end
    end

    def incomplete_steps = steps.reject { complete?(it) }

    def finishable? = incomplete_steps.empty?

    # The step to show when someone opens the wizard: the furthest step that has data, or :finish.
    def current_step
      return :finish if finishable?
      return incomplete_steps.first if organization.departments.exists? || organization.job_roles.exists?
      return :catalogue if organization.country_allowances.exists?
      return :allowances if complete?(:countries)
      :organization
    end

    # Allowances are per country, so that step needs countries first.
    def available?(step) = step != :allowances || complete?(:countries)

    def finish!
      return false unless finishable?
      organization.update!(setup_completed_at: Time.current)
      true
    end
  end
end
