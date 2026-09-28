require "rails_helper"

RSpec.describe Onboarding::Wizard do
  subject(:wizard) { described_class.new(organization) }

  let(:organization) { create(:organization, :pending_setup) }
  let(:india) { create(:country, :india) }

  it "has four steps in order" do
    expect(wizard.steps).to eq(%i[organization countries allowances catalogue])
  end

  describe "#current_step (where to resume, from the data)" do
    it "starts at the organization step for a new organization" do
      expect(wizard.current_step).to eq(:organization)
    end

    it "moves to allowances once countries are chosen" do
      organization.countries << india
      expect(wizard.current_step).to eq(:allowances)
    end

    it "moves to departments & job roles once an allowance exists" do
      create(:country_allowance, organization:, country: india)
      expect(wizard.current_step).to eq(:catalogue)
    end

    it "stays on departments & job roles until both have an entry" do
      organization.countries << india
      create(:department, organization:)
      expect(wizard.current_step).to eq(:catalogue)
    end

    it "is :finish when everything required is in place" do
      organization.countries << india
      create(:department, organization:)
      create(:job_role, organization:)
      expect(wizard.current_step).to eq(:finish)
    end

    it "goes back to countries if the catalogue is done but no country is chosen" do
      create(:department, organization:)
      create(:job_role, organization:)
      expect(wizard.current_step).to eq(:countries)
    end
  end

  describe "#complete?" do
    it "treats the organization step as complete when the organization is valid" do
      expect(wizard.complete?(:organization)).to be(true)
    end

    it "needs at least one country" do
      expect(wizard.complete?(:countries)).to be(false)
      organization.countries << india
      expect(wizard.complete?(:countries)).to be(true)
    end

    it "treats allowances as optional" do
      expect(wizard.complete?(:allowances)).to be(true)
    end

    it "needs at least one department and one job role" do
      create(:department, organization:)
      expect(wizard.complete?(:catalogue)).to be(false)
      create(:job_role, organization:)
      expect(wizard.complete?(:catalogue)).to be(true)
    end
  end

  describe "#finishable? and #incomplete_steps" do
    it "lists what is missing" do
      expect(wizard).not_to be_finishable
      expect(wizard.incomplete_steps).to eq(%i[countries catalogue])
    end

    it "is finishable with a country, a department and a job role" do
      organization.countries << india
      create(:department, organization:)
      create(:job_role, organization:)

      expect(wizard).to be_finishable
      expect(wizard.incomplete_steps).to be_empty
    end
  end

  describe "#available?" do
    it "only offers allowances once countries are chosen" do
      expect(wizard.available?(:allowances)).to be(false)
      organization.countries << india
      expect(wizard.available?(:allowances)).to be(true)
    end

    it "always offers the other steps" do
      expect(%i[organization countries catalogue].map { |step| wizard.available?(step) }).to all(be(true))
    end
  end

  describe "#finish!" do
    it "marks setup complete when finishable" do
      organization.countries << india
      create(:department, organization:)
      create(:job_role, organization:)

      freeze_time do
        expect(wizard.finish!).to be(true)
        expect(organization.reload.setup_completed_at).to eq(Time.current)
      end
    end

    it "does nothing when steps are missing" do
      expect(wizard.finish!).to be(false)
      expect(organization.reload.setup_completed_at).to be_nil
    end
  end
end
