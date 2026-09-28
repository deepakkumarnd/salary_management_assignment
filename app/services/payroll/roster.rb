module Payroll
  # Who is on a country's payroll for a month: everyone employed on at least one day of it (joiners, leavers, people
  # serving notice), never records ended as "recorded in error". Current role and department (they aren't dated).
  class Roster
    def self.employees(organization, country, month)
      organization.employees.where(country:).countable.employed_during(month.start, month.finish)
    end
  end
end
