require "rails_helper"

RSpec.describe Department, type: :model do
  subject { build(:department) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(60) }

  it "is unique per organization, ignoring case" do
    existing = create(:department, name: "Engineering")

    expect(build(:department, organization: existing.organization, name: "engineering")).not_to be_valid
    expect(build(:department, name: "Engineering")).to be_valid
  end

  it "strips surrounding whitespace from the name" do
    expect(build(:department, name: "  Sales ").name).to eq("Sales")
  end
end
