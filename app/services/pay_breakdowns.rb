# Pay breakdowns for a list of employees loaded with Employee.with_basic_pay_as_of(date): pay structures, their role
# allowances and the country allowances are loaded once for the whole list instead of once per row.
#
#   pay = PayBreakdowns.new(Current.organization, employees)
#   pay.for(employee)&.gross
class PayBreakdowns
  def initialize(organization, employees)
    employees = employees.to_a
    country_ids = employees.map(&:country_id).uniq
    @structures = organization.pay_structures.includes(:allowances, :organization)
                              .where(country_id: country_ids, job_role_id: employees.map(&:job_role_id).uniq)
                              .index_by { [ it.country_id, it.job_role_id ] }
    @country_allowances = organization.country_allowances.where(country_id: country_ids).to_a.group_by(&:country_id)
  end

  def for(employee)
    return if employee.basic_pay.nil?

    structure = @structures.fetch([ employee.country_id, employee.job_role_id ])
    structure.breakdown_for(employee.basic_pay, country_allowances: @country_allowances.fetch(employee.country_id, []))
  end
end
