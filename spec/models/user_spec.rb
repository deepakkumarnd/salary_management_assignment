require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  describe "associations" do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:deactivated_by).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:email) }

    it "rejects a malformed email" do
      user.email = "not-an-email"
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("is invalid")
    end

    it "requires a password of at least 12 characters" do
      expect(build(:user, password: "a" * 11)).not_to be_valid
      expect(build(:user, password: "a" * 12)).to be_valid
    end

    it "requires the confirmation to match when given" do
      user = build(:user, password: "correct-horse-battery", password_confirmation: "something-else")
      expect(user).not_to be_valid
      expect(user.errors[:password_confirmation]).to include("doesn't match Password")
    end

    it "does not require a password to update other attributes" do
      user = User.find(create(:user).id)
      user.full_name = "Priya Nair"
      expect(user).to be_valid
    end
  end

  describe "email" do
    it "is normalised to lower case without surrounding spaces" do
      user.email = "  Priya.Nair@Example.TEST "
      expect(user.email).to eq("priya.nair@example.test")
    end

    it "is unique among active accounts, across organizations" do
      create(:user, email: "priya@example.test")
      other = build(:user, email: "PRIYA@example.test")

      expect(other).not_to be_valid
      expect(other.errors[:email]).to include("has already been taken")
    end

    it "can be reused once the account holding it is deactivated" do
      create(:user, :deactivated, email: "priya@example.test")
      expect(build(:user, email: "priya@example.test")).to be_valid
    end
  end

  describe "deactivation" do
    let(:user) { create(:user, :deactivated) }

    it "can't authenticate" do
      expect(user.active_for_authentication?).to be(false)
      expect(user.inactive_message).to eq(:deactivated)
    end

    it "is invisible to Devise's sign-in and password-reset lookups" do
      expect(User.find_for_authentication(email: user.email)).to be_nil
      expect(User.find_first_by_auth_conditions(email: user.email)).to be_nil
    end

    it "leaves active accounts findable" do
      active = create(:user)
      expect(User.find_for_authentication(email: active.email.upcase)).to eq(active)
      expect(active.active_for_authentication?).to be(true)
    end
  end
end
