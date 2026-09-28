# Defence in depth against cross-tenant references: controllers only offer records from Current.organization, and
# this validation refuses any association that points into another organization anyway.
#
#   validates_same_organization :department, :job_role
module SameOrganization
  extend ActiveSupport::Concern

  class_methods do
    def validates_same_organization(*associations)
      validate do
        associations.each do |association|
          record = public_send(association)
          next if record.nil? || record.organization_id == organization_id
          errors.add(association, "must belong to the same organization")
        end
      end
    end
  end
end
