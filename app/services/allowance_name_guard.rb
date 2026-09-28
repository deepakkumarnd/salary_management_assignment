# "A role cannot redefine a country allowance, and vice versa": within one organization and country, an allowance
# name belongs either to the country or to roles, never both, so a breakdown never shows two "HRA" lines.
# The rule spans two tables, so no unique index can express it; both models validate through here. Rails opens
# SQLite write transactions as IMMEDIATE, so the check and the write can't interleave with another writer.
class AllowanceNameGuard
  def self.conflict_for_role_allowance(allowance)
    structure = allowance.pay_structure
    return if structure.nil? || structure.country.nil? || allowance.name.blank?

    existing = CountryAllowance.where(organization_id: structure.organization_id, country_id: structure.country_id)
                               .where(same_name(CountryAllowance, allowance.name)).first
    "#{existing.name} is already a country allowance in #{structure.country.name}" if existing
  end

  def self.conflict_for_country_allowance(allowance)
    return if allowance.organization_id.nil? || allowance.country.nil? || allowance.name.blank?

    matches = PayStructureAllowance.joins(pay_structure: :job_role)
                                   .where(pay_structures: { organization_id: allowance.organization_id,
                                                            country_id: allowance.country_id })
                                   .where(same_name(PayStructureAllowance, allowance.name))
                                   .pluck("pay_structure_allowances.name", "job_roles.name")
    return if matches.empty?

    roles = matches.map(&:last).sort_by(&:downcase).to_sentence
    "#{matches.first.first} is already a role allowance for #{roles} in #{allowance.country.name}"
  end

  def self.same_name(model, name) = model.arel_table[:name].lower.eq(name.strip.downcase)
  private_class_method :same_name
end
