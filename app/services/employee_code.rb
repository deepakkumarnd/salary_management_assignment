# Readable employee IDs (ACME-00042) from a per-organization counter. The counter is bumped with a single
# UPDATE … RETURNING inside the employee's create transaction, so concurrent creates never get the same number and a
# failed create gives its number back. Numbers are never reused, and grow past five digits naturally.
class EmployeeCode
  def self.next_for(organization) = format_for(organization, reserve(organization, 1).first)

  # Reserves a block of numbers with one atomic bump of the counter (bulk inserts: imports, demo data).
  def self.reserve(organization, count)
    sql = Organization.sanitize_sql_array([ <<~SQL, count, organization.id ])
      UPDATE organizations SET next_employee_number = next_employee_number + ?
      WHERE id = ? RETURNING next_employee_number
    SQL
    after_last = Organization.with_connection { it.exec_query(sql).rows.first.first }
    (after_last - count)...after_last
  end

  def self.format_for(organization, number) = format("%s-%05d", organization.employee_code_prefix, number)
end
