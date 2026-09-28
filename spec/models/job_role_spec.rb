require "rails_helper"

RSpec.describe JobRole, type: :model do
  subject { build(:job_role) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(60) }

  it "is unique per organization, ignoring case" do
    existing = create(:job_role, name: "Engineering")

    expect(build(:job_role, organization: existing.organization, name: "engineering")).not_to be_valid
    expect(build(:job_role, name: "Engineering")).to be_valid
  end

  it "strips surrounding whitespace from the name" do
    expect(build(:job_role, name: "  Sales ").name).to eq("Sales")
  end
end
