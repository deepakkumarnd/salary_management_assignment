require "rails_helper"

RSpec.describe Onboarding::CatalogueForm do
  let(:organization) { create(:organization, :pending_setup) }

  def form(departments:, job_roles:)
    described_class.new(organization, departments:, job_roles:)
  end

  it "suggests departments and job roles for an empty organization" do
    suggestions = described_class.new(organization)

    expect(suggestions.departments.lines.map(&:chomp)).to include("Engineering", "Sales")
    expect(suggestions.job_roles.lines.map(&:chomp)).to include("Software Engineer", "Accountant")
  end

  it "shows the organization's own lists once it has them" do
    create(:department, organization:, name: "Research")
    create(:job_role, organization:, name: "Chemist")

    existing = described_class.new(organization)

    expect(existing.departments).to eq("Research")
    expect(existing.job_roles).to eq("Chemist")
  end

  it "creates one record per non-blank line, trimmed and de-duplicated ignoring case" do
    expect(form(departments: "Engineering\r\n\r\n  Sales  \nsales\n", job_roles: "Accountant").save).to be(true)

    expect(organization.departments.order(:name).pluck(:name)).to eq(%w[Engineering Sales])
    expect(organization.job_roles.pluck(:name)).to eq(%w[Accountant])
  end

  it "removes names no longer listed and keeps the ones still listed" do
    engineering = create(:department, organization:, name: "Engineering")
    create(:department, organization:, name: "Legal")
    create(:job_role, organization:, name: "Accountant")

    form(departments: "engineering\nSales", job_roles: "Accountant").save

    expect(organization.departments.order(:name).pluck(:name)).to eq(%w[engineering Sales])   # the casing typed
    expect(organization.departments).to include(engineering)                                     # same record
  end

  it "needs at least one of each" do
    result = form(departments: " \n", job_roles: "")

    expect(result.save).to be(false)
    expect(result.errors[:departments]).to include("add at least one department")
    expect(result.errors[:job_roles]).to include("add at least one job role")
  end

  it "reports invalid names and saves nothing" do
    result = form(departments: "Engineering\n#{'x' * 61}", job_roles: "Accountant")

    expect(result.save).to be(false)
    expect(result.errors[:departments].first).to start_with("xxxxxxxx")
    expect(organization.departments).to be_empty
    expect(organization.job_roles).to be_empty
  end

  it "only ever touches its own organization" do
    other = create(:department, name: "Engineering")

    form(departments: "Sales", job_roles: "Accountant").save

    expect(Department.exists?(other.id)).to be(true)
  end
end
