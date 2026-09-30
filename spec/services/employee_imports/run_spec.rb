require "rails_helper"

RSpec.describe EmployeeImports::Run do
  let(:organization) { create(:organization, employee_code_prefix: "ACME") }
  let(:user) { create(:user, organization:) }
  let(:india) { create(:country, :india) }
  let(:engineer) { create(:job_role, organization:, name: "Software Engineer") }
  let!(:engineering) { create(:department, organization:, name: "Engineering") }
  let!(:structure) { create(:pay_structure, organization:, country: india, job_role: engineer) }
  let(:today) { Date.new(2026, 9, 30) }

  around { |example| travel_to(Time.utc(2026, 9, 30, 10)) { example.run } }

  let(:header) { "name,email,department,designation,basic_pay,country,hire_date,employment_type\n" }

  def import_of(csv, filename: "people.csv")
    EmployeeImport.create!(organization:, uploaded_by: user,
                           file: { io: StringIO.new(csv), filename:, content_type: "text/csv" })
  end

  def run(csv)
    import_of(csv).tap { described_class.new(it).call }.reload
  end

  def reasons(import) = import.skipped_rows.order(:row_number).to_h { [ it.row_number, it.reasons ] }

  it "creates employees with a hire revision each, numbered from the organization's sequence" do
    import = run(header + <<~CSV)
      Priya Nair,Priya@Acme.test,Engineering,Software Engineer,"12,00,000",India,2026-04-01,full_time
      Rahul  Verma,rahul@acme.test,engineering,software engineer,900000,india,,
    CSV

    expect(import).to have_attributes(status: "completed", total_rows: 2, processed_rows: 2, created_count: 2,
                                      skipped_count: 0, started_at: be_present, finished_at: be_present)
    priya, rahul = organization.employees.order(:employee_code).to_a
    expect(priya).to have_attributes(employee_code: "ACME-00001", full_name: "Priya Nair", email: "priya@acme.test",
                                     country: india, job_role: engineer, department: engineering,
                                     employment_type: "full_time", hire_date: Date.new(2026, 4, 1), updated_by: user)
    expect(rahul).to have_attributes(employee_code: "ACME-00002", full_name: "Rahul Verma", hire_date: today,
                                     employment_type: "full_time", department: engineering, job_role: engineer)
    expect(priya.salary_revisions.sole).to have_attributes(reason: "hire", effective_on: Date.new(2026, 4, 1),
                                                          basic_pay: 1_200_000, created_by: user,
                                                          notes: "Imported from people.csv")
    expect(rahul.basic_pay_on(today)).to eq(900_000)
    expect(organization.reload.next_employee_number).to eq(3)
  end

  it "leaves every imported employee valid by the model's own rules" do
    run(header + "Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,2026-04-01,part_time\n")

    employee = organization.employees.sole
    expect(employee).to be_valid
    expect(employee.salary_revisions.sole).to be_valid
  end

  it "accepts column names in any case and order, a byte order mark, blank lines and extra columns" do
    import = run("﻿Phone Number, Country ,Basic Pay,EMAIL,Designation,Department,Name\n" \
                 "555-0100,India,1000000,priya@acme.test,Software Engineer,Engineering,Priya Nair\n\n,,,,,,\n")

    expect(import).to have_attributes(status: "completed", total_rows: 1, created_count: 1)
  end

  it "bumps the pay data version so cached insights recompute" do
    expect { run(header + "Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,\n") }
      .to change { organization.reload.pay_data_version }
  end

  describe "departments and designations" do
    it "creates the ones that don't exist yet, once each, and notes them on the import" do
      designer = create(:job_role, organization:, name: "Designer")
      create(:pay_structure, organization:, country: india, job_role: designer)

      import = run(header + <<~CSV)
        Priya Nair,priya@acme.test,Product,Designer,1200000,India,,
        Rahul Verma,rahul@acme.test,product,Designer,1200000,India,,
      CSV

      expect(import.created_count).to eq(2)
      expect(organization.departments.where(name: "Product").count).to eq(1)
      expect(import.new_departments).to eq([ "Product" ])
      expect(import.new_job_roles).to eq([])
    end

    it "creates a new designation but skips its rows until it has a pay structure in that country" do
      import = run(header + <<~CSV)
        Priya Nair,priya@acme.test,Engineering,Data Analyst,1200000,India,,
        Rahul Verma,rahul@acme.test,Engineering,Data Analyst,1200000,India,,
      CSV

      analyst = organization.job_roles.find_by!(name: "Data Analyst")
      expect(import).to have_attributes(created_count: 0, skipped_count: 2, new_job_roles: [ "Data Analyst" ])
      expect(reasons(import)[2]).to eq([ "Designation Data Analyst has no pay structure in India yet. " \
                                         "Create one in Pay policy, then upload the skipped rows again." ])
      expect(import.missing_pay_structures).to eq([ { "country_id" => india.id, "country" => "India",
                                                      "job_role_id" => analyst.id, "job_role" => "Data Analyst", "rows" => 2 } ])
    end

    it "doesn't create departments or designations for rows that are invalid anyway" do
      import = run(header + "Priya Nair,not-an-email,Product,Designer,1200000,India,,\n")

      expect(import.skipped_count).to eq(1)
      expect(organization.departments.exists?(name: "Product")).to be(false)
      expect(organization.job_roles.exists?(name: "Designer")).to be(false)
    end
  end

  describe "emails" do
    it "skips an email ever used in the organization, by a current or a former employee" do
      create(:employee, pay_structure: structure, email: "current@acme.test")
      create(:employee, :exited, pay_structure: structure, email: "former@acme.test")

      import = run(header + <<~CSV)
        Current,Current@acme.test,Engineering,Software Engineer,1200000,India,,
        Former,former@acme.test,Engineering,Software Engineer,1200000,India,,
        New,new@acme.test,Engineering,Software Engineer,1200000,India,,
      CSV

      expect(import).to have_attributes(created_count: 1, skipped_count: 2)
      expect(reasons(import)[2]).to eq([ "Email is already used by employee ACME-00001" ])
      expect(reasons(import)[3]).to eq([ "Email is already used by employee ACME-00002" ])
    end

    it "allows an email that another organization uses" do
      globex = create(:organization, employee_code_prefix: "GLBX")
      create(:employee, pay_structure: create(:pay_structure, organization: globex, country: india), email: "priya@acme.test")

      import = run(header + "Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,\n")
      expect(import.created_count).to eq(1)
    end

    it "keeps the first row with an email and skips later ones, within a batch and across batches" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      import = run(header + <<~CSV)
        Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,
        Priya Again,priya@acme.test,Engineering,Software Engineer,1200000,India,,
        Rahul Verma,rahul@acme.test,Engineering,Software Engineer,1200000,India,,
        Priya Third,PRIYA@acme.test,Engineering,Software Engineer,1200000,India,,
      CSV

      expect(import).to have_attributes(created_count: 2, skipped_count: 2)
      expect(reasons(import)).to eq(3 => [ "Email is already used on row 2 of this file" ],
                                    5 => [ "Email is already used by employee ACME-00001" ])
    end

    it "lets a later row use an email whose earlier row was skipped for another reason" do
      import = run(header + <<~CSV)
        Priya Nair,priya@acme.test,Engineering,Software Engineer,0,India,,
        Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,
      CSV

      expect(import).to have_attributes(created_count: 1, skipped_count: 1)
    end

    it "skips only the clashing row when someone adds the same email in the app during the import" do
      import = import_of(header + <<~CSV)
        Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,
        Rahul Verma,rahul@acme.test,Engineering,Software Engineer,1200000,India,,
      CSV
      run = described_class.new(import)
      allow(run).to receive(:check_emails_not_used).and_wrap_original do |original, rows|
        original.call(rows)
        create(:employee, pay_structure: structure, email: "rahul@acme.test")   # added meanwhile
      end

      run.call

      expect(import.reload).to have_attributes(status: "completed", created_count: 1, skipped_count: 1)
      expect(reasons(import)[3]).to eq([ "Email was used by an employee added while this file was being imported" ])
      expect(organization.employees.pluck(:email)).to contain_exactly("priya@acme.test", "rahul@acme.test")
    end
  end

  it "reports every reason a row is skipped, and keeps what it said" do
    germany = create(:country, :germany)
    import = run(header + <<~CSV)
      ,bad-email,Engineering,Software Engineer,"12.5",India,2099-01-01,intern
      Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,Germany,,
      Rahul Verma,rahul@acme.test,Engineering,Software Engineer,1200000,Atlantis,30/09/2026,
    CSV

    expect(germany).to be_persisted
    expect(import).to have_attributes(created_count: 0, skipped_count: 3)
    expect(reasons(import)).to eq(
      2 => [ "Name can't be blank", "Email is invalid", "Basic pay must be an integer",
             "Hire date can't be in the future", "Employment type must be full_time, part_time or contractor" ],
      3 => [ "Country Germany is not one of the organization's operating countries" ],
      4 => [ "Hire date must be a date written as YYYY-MM-DD, like 2026-09-30", "Country \"Atlantis\" is not a supported country" ]
    )
    expect(import.skipped_rows.find_by!(row_number: 3)).to have_attributes(
      email: "priya@acme.test",
      data: { "name" => "Priya Nair", "email" => "priya@acme.test", "department" => "Engineering",
              "designation" => "Software Engineer", "basic_pay" => "1200000", "country" => "Germany",
              "hire_date" => "", "employment_type" => "" }
    )
  end

  it "logs each skipped row with its reasons" do
    allow(Rails.logger).to receive(:info).and_call_original

    import = run(header + "Priya Nair,bad-email,Engineering,Software Engineer,1200000,India,,\n")

    expect(Rails.logger).to have_received(:info)
      .with("[EmployeeImport #{import.id}] Skipped row 2 (bad-email): Email is invalid")
  end

  describe "a file that can't be imported" do
    it "fails without creating anyone when required columns are missing" do
      import = run("name,email,department\nPriya Nair,priya@acme.test,Engineering\n")

      expect(import).to have_attributes(status: "failed", created_count: 0, finished_at: be_present)
      expect(import.error_message).to eq("The file is missing the designation, basic_pay, and country columns. Its first row " \
                                         "must be the column names: name, email, department, designation, basic_pay, " \
                                         "country, hire_date, employment_type (the last two are optional).")
    end

    it "fails on an empty file, or one with only the column names" do
      expect(run("")).to have_attributes(status: "failed", error_message: "The file is empty.")
      expect(run(header)).to have_attributes(status: "failed", error_message: "The file has no employee rows below the column names.")
    end

    it "fails without creating anyone when it has more rows than the limit" do
      stub_const("EmployeeImport::MAX_ROWS", 2)
      row = "Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,\n"

      import = run(header + row * 3)

      expect(import).to have_attributes(status: "failed", error_message: "The file has more than 2 rows. Split it into smaller files.")
      expect(organization.employees).to be_empty
    end

    it "fails without creating anyone when the file isn't valid CSV further down" do
      import = run(header + "Priya Nair,priya@acme.test,Engineering,Software Engineer,1200000,India,,\n\"unclosed,quote\n")

      expect(import.status).to eq("failed")
      expect(import.error_message).to start_with("The file couldn't be read as CSV")
      expect(organization.employees).to be_empty
    end

    it "fails without creating anyone when the file isn't UTF-8" do
      import = run((header + "Zoë Smith,zoe@acme.test,Engineering,Software Engineer,1200000,India,,\n").encode("ISO-8859-1"))

      expect(import.status).to eq("failed")
      expect(import.error_message).to include("Save it as CSV UTF-8")
    end
  end

  describe "batches" do
    before { stub_const("#{described_class}::BATCH_SIZE", 2) }

    let(:csv) do
      header + (1..5).map { "Person #{it},person#{it}@acme.test,Engineering,Software Engineer,1200000,India,,\n" }.join
    end

    it "saves progress with each batch" do
      import = import_of(csv)
      run = described_class.new(import)
      progress = []
      allow(run).to receive(:write).and_wrap_original do |original, rows|
        original.call(rows)
        progress << import.reload.slice(:processed_rows, :created_count).values
      end

      run.call

      expect(progress).to eq([ [ 2, 2 ], [ 4, 4 ], [ 5, 5 ] ])
      expect(import.reload).to have_attributes(processed_rows: 5, created_count: 5)
    end

    it "resumes after the last saved batch when a job stopped half-way, creating and skipping nothing twice" do
      import = import_of(csv)
      calls = 0
      failing = described_class.new(import)
      allow(failing).to receive(:write).and_wrap_original do |original, rows|
        raise "worker killed" if (calls += 1) == 2
        original.call(rows)
      end
      expect { failing.call }.to raise_error("worker killed")
      expect(import.reload).to have_attributes(status: "processing", processed_rows: 2, created_count: 2)

      described_class.new(import.reload).call

      expect(import.reload).to have_attributes(status: "completed", total_rows: 5, processed_rows: 5, created_count: 5,
                                               skipped_count: 0)
      expect(organization.employees.order(:employee_code).pluck(:email))
        .to eq((1..5).map { "person#{it}@acme.test" })
    end
  end
end
