module Onboarding
  # The "departments & job roles" step: two editable lists, one name per line, pre-filled with suggestions.
  # Saving makes the organization's departments and job roles match the lists.
  class CatalogueForm
    include ActiveModel::Model

    SUGGESTED_DEPARTMENTS = [
      "Customer Support", "Engineering", "Finance", "Human Resources", "Marketing", "Operations", "Product", "Sales"
    ].freeze
    SUGGESTED_JOB_ROLES = [
      "Account Manager", "Accountant", "Customer Support Specialist", "Data Analyst", "Designer",
      "Engineering Manager", "Finance Manager", "HR Generalist", "Marketing Specialist", "Operations Manager",
      "Product Manager", "Recruiter", "Sales Executive", "Senior Software Engineer", "Software Engineer"
    ].freeze

    attr_reader :organization, :departments, :job_roles

    def initialize(organization, departments: nil, job_roles: nil)
      @organization = organization
      @departments = departments || current_or_suggested(Department, SUGGESTED_DEPARTMENTS)
      @job_roles = job_roles || current_or_suggested(JobRole, SUGGESTED_JOB_ROLES)
    end

    def save
      errors.clear
      errors.add(:departments, "add at least one department") if names(departments).empty?
      errors.add(:job_roles, "add at least one job role") if names(job_roles).empty?
      return false if errors.any?

      ActiveRecord::Base.transaction do
        sync(Department, names(departments), :departments)
        sync(JobRole, names(job_roles), :job_roles)
        raise ActiveRecord::Rollback if errors.any?
      end
      errors.empty?
    end

    private

    def current_or_suggested(model, suggestions)
      (model.where(organization:).order(:name).pluck(:name).presence || suggestions).join("\n")
    end

    def names(text) = text.to_s.lines.map(&:strip).compact_blank.uniq(&:downcase)

    # Keeps records still listed (updating their casing), removes the rest and creates the new names.
    def sync(model, names, attribute)
      wanted = names.index_by(&:downcase)

      model.where(organization:).find_each do |record|
        if (name = wanted.delete(record.name.downcase))
          record.update(name:) || copy_errors(record, attribute)
        elsif !record.destroy
          errors.add(attribute, "#{record.name} can't be removed because it is in use")
        end
      end

      wanted.each_value do |name|
        record = model.create(organization:, name:)
        copy_errors(record, attribute) unless record.persisted?
      end
    end

    def copy_errors(record, attribute)
      record.errors.messages_for(:name).each { errors.add(attribute, "#{record.name}: #{it}") }
    end
  end
end
