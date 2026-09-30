require "rails_helper"
require "csv"

RSpec.describe "Employee imports", type: :request do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:, full_name: "Deepak Kumar") }
  let(:india) { create(:country, :india) }

  before { sign_in user }

  def csv_upload(content, filename: "people.csv")
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename)
  end

  def import_with(organization: self.organization, **attributes)
    EmployeeImport.create!(organization:, uploaded_by: create(:user, organization:),
                           file: { io: StringIO.new("name\n"), filename: "people.csv", content_type: "text/csv" },
                           **attributes)
  end

  describe "POST /employee_imports" do
    it "stores the file, queues the import and shows its progress" do
      expect {
        post employee_imports_path, params: { employee_import: { file: csv_upload("name,email\n") } }
      }.to have_enqueued_job(EmployeeImportJob)

      import = organization.employee_imports.sole
      expect(import).to have_attributes(status: "queued", uploaded_by: user, filename: "people.csv")
      expect(import.file.download).to eq("name,email\n")
      expect(response).to redirect_to(employee_import_path(import))

      follow_redirect!
      expect(response.body).to include("people.csv was uploaded", "Waiting to start", 'data-controller="auto-refresh"')
    end

    it "refuses a missing file, a file that isn't a CSV, and a file over the size limit" do
      post employee_imports_path, params: { employee_import: { file: "" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("File must be chosen")

      post employee_imports_path, params: { employee_import: { file: csv_upload("x", filename: "people.xlsx") } }
      expect(response.body).to include("File must be a .csv file")

      stub_const("EmployeeImport::MAX_FILE_SIZE", 5)
      post employee_imports_path, params: { employee_import: { file: csv_upload("name,email\n") } }
      expect(response.body).to include("File is too large")

      expect(EmployeeImport.count).to eq(0)
      expect(EmployeeImportJob).not_to have_been_enqueued
    end
  end

  describe "GET /employee_imports/:id" do
    it "shows the results: counts, new names, missing pay structures and skipped rows with their reasons" do
      analyst = create(:job_role, organization:, name: "Data Analyst")
      import = import_with(status: "completed", total_rows: 3, processed_rows: 3, created_count: 1, skipped_count: 2,
                           new_departments: [ "Product" ], new_job_roles: [ "Data Analyst" ], finished_at: Time.current,
                           missing_pay_structures: [ { "country_id" => india.id, "country" => "India",
                                                       "job_role_id" => analyst.id, "job_role" => "Data Analyst", "rows" => 1 } ])
      import.skipped_rows.create!(row_number: 3, email: "bad", data: { "name" => "Rahul Verma" }, reasons: [ "Email is invalid" ])

      get employee_import_path(import)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Completed", "New departments:", "Product", "New job roles:", "Data Analyst in India",
                                       "Rahul Verma", "Email is invalid", "Download skipped rows (CSV)")
      expect(response.body).to include(new_pay_structure_path(country_id: india.id, job_role_id: analyst.id).gsub("&", "&amp;"))
      expect(response.body).not_to include('data-controller="auto-refresh"')
    end

    it "never shows another organization's import" do
      get employee_import_path(import_with(organization: create(:organization, employee_code_prefix: "GLBX")))
      expect(response).to have_http_status(:not_found)
    end

    it "never downloads another organization's skipped rows" do
      get employee_import_skipped_rows_path(import_with(organization: create(:organization, employee_code_prefix: "GLBX")),
                                            format: :csv)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "lists recent imports" do
    import_with(status: "completed", total_rows: 1_200, created_count: 1_150, skipped_count: 50)

    get employee_imports_path

    expect(response.body).to include("people.csv", "Completed", "1,200", "1,150")
  end

  it "offers a template with the columns and an example row" do
    get template_employee_imports_path

    expect(response.headers["Content-Disposition"]).to include("employee-import-template.csv")
    csv = CSV.parse(response.body.delete_prefix("﻿"), headers: true)
    expect(csv.headers).to eq(EmployeeImports::Row::COLUMNS)
    expect(csv.first["designation"]).to eq("Software Engineer")
  end

  it "downloads the skipped rows as a CSV that can be fixed and uploaded again" do
    import = import_with(status: "completed", skipped_count: 2)
    import.skipped_rows.create!(row_number: 2, email: "bad", reasons: [ "Email is invalid", "Basic pay is not a number" ],
                                data: { "name" => "Priya Nair", "email" => "bad", "basic_pay" => "x", "country" => "India" })
    import.skipped_rows.create!(row_number: 5, email: "rahul@acme.test", reasons: [ "Email is already used by employee ACME-00001" ],
                                data: { "name" => "Rahul Verma", "email" => "rahul@acme.test" })

    get employee_import_skipped_rows_path(import, format: :csv)

    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("attachment", "people-skipped-rows.csv")
    rows = CSV.parse(response.body.delete_prefix("﻿"), headers: true)
    expect(rows.headers).to eq(EmployeeImports::Row::COLUMNS + %w[original_row reasons])
    expect(rows.map { it.to_h.values_at("name", "email", "country", "original_row", "reasons") }).to eq([
      [ "Priya Nair", "bad", "India", "2", "Email is invalid; Basic pay is not a number" ],
      [ "Rahul Verma", "rahul@acme.test", nil, "5", "Email is already used by employee ACME-00001" ]
    ])
  end

  it "preselects the job role when creating a missing pay structure from an import" do
    analyst = create(:job_role, organization:, name: "Data Analyst")
    organization.countries << india

    get new_pay_structure_path(country_id: india.id, job_role_id: analyst.id)

    expect(response.body).to match(/<option selected="selected" value="#{analyst.id}">Data Analyst/)
  end
end
