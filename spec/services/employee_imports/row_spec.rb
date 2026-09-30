require "rails_helper"

RSpec.describe EmployeeImports::Row do
  let(:today) { Date.new(2026, 9, 30) }
  let(:fields) do
    { "name" => " Priya   Nair ", "email" => " Priya@Acme.TEST ", "department" => "Engineering",
      "designation" => "Software Engineer", "basic_pay" => "12,00,000", "country" => "India",
      "hire_date" => "2026-04-01", "employment_type" => "Part time" }
  end

  def row(**overrides) = described_class.from_csv(fields.merge(overrides.stringify_keys), row_number: 2, today:)
  def errors_on(row, attribute) = row.tap(&:validate).errors[attribute]

  around { |example| travel_to(Time.utc(2026, 9, 30, 10)) { example.run } }

  it "normalises the values the way Employee does" do
    expect(row).to be_valid
    expect(row).to have_attributes(name: "Priya Nair", email: "priya@acme.test", basic_pay: "1200000",
                                   hire_date: Date.new(2026, 4, 1), employment_type: "part_time")
  end

  it "defaults a blank hire date to today and a blank employment type to full time" do
    expect(row(hire_date: "", employment_type: nil)).to have_attributes(hire_date: today, employment_type: "full_time")
  end

  it "keeps the uploaded values, trimmed, for the skipped-rows download" do
    expect(row(phone: "555-0100").data).to eq(
      "name" => "Priya   Nair", "email" => "Priya@Acme.TEST", "department" => "Engineering",
      "designation" => "Software Engineer", "basic_pay" => "12,00,000", "country" => "India",
      "hire_date" => "2026-04-01", "employment_type" => "Part time"
    )
  end

  it "accepts only YYYY-MM-DD dates that exist" do
    expect(errors_on(row(hire_date: "2026-02-30"), :hire_date_text)).to be_present
    expect(errors_on(row(hire_date: "01/04/2026"), :hire_date_text)).to be_present
  end

  # The importer writes with insert_all, so its checks must refuse what Employee refuses.
  describe "in step with Employee's validations" do
    let(:organization) { create(:organization) }
    let(:structure) { create(:pay_structure, organization:) }

    def employee_for(row)
      Employee.new(organization:, country: structure.country, job_role: structure.job_role,
                   department: create(:department, organization:), recorded_by: create(:user, organization:),
                   full_name: row.name, email: row.email, hire_date: row.hire_date, initial_basic_pay: row.basic_pay,
                   employment_type: row.employment_type)
    end

    it "accepts a row Employee accepts" do
      expect(row).to be_valid
      expect(employee_for(row)).to be_valid
    end

    {
      "a blank name" => [ { name: " " }, :name, :full_name ],
      "a name over 100 characters" => [ { name: "x" * 101 }, :name, :full_name ],
      "an invalid email" => [ { email: "priya@" }, :email, :email ],
      "a blank email" => [ { email: "" }, :email, :email ],
      "a zero basic pay" => [ { basic_pay: "0" }, :basic_pay, :initial_basic_pay ],
      "a fractional basic pay" => [ { basic_pay: "1200.50" }, :basic_pay, :initial_basic_pay ],
      "a basic pay that isn't a number" => [ { basic_pay: "twelve" }, :basic_pay, :initial_basic_pay ],
      "a basic pay over the maximum" => [ { basic_pay: (10**12).to_s }, :basic_pay, :initial_basic_pay ],
      "a hire date in the future" => [ { hire_date: "2026-10-01" }, :hire_date_text, :hire_date ],
      "an unknown employment type" => [ { employment_type: "intern" }, :employment_type, :employment_type ]
    }.each do |label, (overrides, row_attribute, employee_attribute)|
      it "refuses #{label}, like Employee" do
        invalid = row(**overrides)

        expect(errors_on(invalid, row_attribute)).to be_present
        employee = employee_for(invalid)
        employee.validate
        expect(employee.errors[employee_attribute]).to be_present
      end
    end
  end
end
