# Readable employee IDs (ACME-00042) from a per-organization counter. The counter is bumped with a single
# UPDATE … RETURNING inside the employee's create transaction, so concurrent creates never get the same number and a
# failed create gives its number back. Numbers are never reused, and grow past five digits naturally.
class EmployeeCode
  def self.next_for(organization)
    sql = Organization.sanitize_sql_array([ <<~SQL, organization.id ])
      UPDATE organizations SET next_employee_number = next_employee_number + 1
      WHERE id = ? RETURNING next_employee_number - 1
    SQL
    number = Organization.with_connection { it.exec_query(sql).rows.first.first }
    format("%s-%05d", organization.employee_code_prefix, number)
  end
end
