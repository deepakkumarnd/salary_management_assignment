require "rails_helper"

RSpec.describe "Pay policy", type: :system do
  let(:organization) { create(:organization, name: "Acme Corporation") }
  let(:user) { create(:user, organization:) }

  before do
    organization.countries << create(:country, :india)
    create(:job_role, organization:, name: "Software Engineer")
    create(:job_role, organization:, name: "Accountant")
    sign_in user
  end

  it "sets up a country allowance and a role's pay structure, and shows the resulting pay" do
    visit root_path
    click_link "Pay policy"
    click_link "India"

    click_link "Add country allowance"
    fill_in "Name", with: "HRA"
    fill_in "Percent of basic", with: "40"
    click_button "Save allowance"
    expect(page).to have_text("HRA was added")

    click_link "Add pay structure"
    select "Software Engineer", from: "Job role"
    fill_in "Default basic pay", with: "12,00,000"
    fill_in "Target variable pay", with: "10"
    fill_in "Overtime rate", with: "150"
    within("#role-allowances") do
      find_all("input[name$='[name]']").last.fill_in(with: "Special")
      find_all("input[name$='[percent]']").last.fill_in(with: "15")
    end
    click_button "Save pay structure"

    expect(page).to have_text("Pay structure for Software Engineer was saved")
    within("tr", text: "Software Engineer") do
      expect(page).to have_text("₹12,00,000")
      expect(page).to have_text("Special 15%")
      expect(page).to have_text("₹18,60,000")   # gross: 12,00,000 + HRA 4,80,000 + Special 1,80,000
      expect(page).to have_text("₹20,46,000")   # total target: gross + 10%
    end
    expect(page).to have_text("No pay structure yet: Accountant")

    # A country allowance can't take a name a role already uses
    click_link "Add country allowance"
    fill_in "Name", with: "Special"
    fill_in "Percent of basic", with: "5"
    click_button "Save allowance"
    expect(page).to have_text("Special is already a role allowance for Software Engineer in India")
  end
end
