require "rails_helper"

RSpec.describe Country, type: :model do
  subject { build(:country) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:name) }

  it "requires a three-letter ISO currency code" do
    expect(build(:country, currency_code: "INR")).to be_valid
    expect(build(:country, currency_code: "IN")).not_to be_valid
    expect(build(:country, currency_code: "inr")).not_to be_valid
  end
end
