# A CSV row an import didn't create an employee from, with every reason. Written in bulk by EmployeeImports::Run.
class EmployeeImportSkippedRow < ApplicationRecord
  belongs_to :employee_import
end
