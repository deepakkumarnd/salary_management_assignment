require "csv"

# Upload a CSV of new employees (new/create), follow its import (show) and look back at earlier ones (index).
# The rows are imported in the background by EmployeeImportJob.
class EmployeeImportsController < AuthenticatedController
  include Pagy::Method

  SKIPPED_PER_PAGE = 50

  def index
    @imports = Current.organization.employee_imports.includes(:uploaded_by, file_attachment: :blob)
                      .order(created_at: :desc).limit(25)
  end

  def new
    @import = Current.organization.employee_imports.build
  end

  def create
    @import = Current.organization.employee_imports.build(uploaded_by: Current.user, file: params.dig(:employee_import, :file))
    if @import.save
      EmployeeImportJob.perform_later(@import)
      redirect_to employee_import_path(@import), notice: "#{@import.filename} was uploaded. Its rows are being imported."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @import = Current.organization.employee_imports.find(params[:id])
    @pagy, @skipped_rows = pagy(:offset, @import.skipped_rows.order(:row_number), limit: SKIPPED_PER_PAGE,
                                page: [ params[:page].to_i, 1 ].max)
    @existing_pay_structures = Current.organization.pay_structures.pluck(:country_id, :job_role_id).to_set
  end

  def template
    csv = CSV.generate_line(EmployeeImports::Row::COLUMNS) +
          CSV.generate_line([ "Priya Nair", "priya.nair@example.com", "Engineering", "Software Engineer", "1200000",
                              "India", Date.current.iso8601, "full_time" ])
    send_data "﻿#{csv}", filename: "employee-import-template.csv", type: "text/csv; charset=utf-8"
  end
end
