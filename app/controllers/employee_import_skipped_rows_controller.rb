require "csv"

# The rows an import skipped, as a CSV with the import's own columns first, so HR can fix them and upload the file
# again (the row and reasons columns are ignored on upload). Streamed, since a large file can skip many rows.
class EmployeeImportSkippedRowsController < AuthenticatedController
  COLUMNS = EmployeeImports::Row::COLUMNS + %w[original_row reasons]

  def show
    import = Current.organization.employee_imports.find(params[:employee_import_id])

    headers["Content-Type"] = "text/csv; charset=utf-8"
    headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(
      disposition: "attachment", filename: "#{File.basename(import.filename, ".*")}-skipped-rows.csv"
    )
    headers["Last-Modified"] = Time.current.httpdate   # stops Rack::ETag from buffering the whole body to hash it
    self.response_body = Enumerator.new do |out|
      out << "﻿#{CSV.generate_line(COLUMNS)}"
      import.skipped_rows.find_each do |row|   # ids follow row order
        out << CSV.generate_line(row.data.values_at(*EmployeeImports::Row::COLUMNS) +
                                 [ row.row_number, row.reasons.join("; ") ])
      end
    end
  end
end
