require "rails_helper"

RSpec.describe "Sign in and organization setup", type: :system do
  let(:organization) { create(:organization, :pending_setup, name: "ACME", employee_code_prefix: "ACME") }
  let!(:user) { create(:user, organization:, email: "hr@acme.test", password: "correct-horse-battery") }

  before do
    create(:country, :india)
    create(:country, :germany)
  end

  it "walks a new HR user from sign-in through setup into the app" do
    visit root_path
    fill_in "Email", with: "hr@acme.test"
    fill_in "Password", with: "correct-horse-battery"
    click_button "Sign in"

    # Step 1: organization
    expect(page).to have_css(".steps .step-primary", text: "Organization")
    fill_in "Organization name", with: "Acme Corporation"
    fill_in "Employee ID prefix", with: "acme"
    fill_in "Standard hours per week", with: "40"
    click_button "Save & continue"

    # Step 2: countries
    expect(page).to have_css("h2", text: "Countries")
    click_button "Save & continue"
    expect(page).to have_text("Choose at least one country")
    check "India"
    check "Germany"
    click_button "Save & continue"

    # Step 3: country allowances
    expect(page).to have_css("h2", text: "Country allowances")
    within("section", text: "India") do
      first("input[name$='[name]']").fill_in(with: "HRA")
      first("input[name$='[percent]']").fill_in(with: "40")
    end
    click_button "Save & continue"

    # Step 4: departments & job roles (suggestions pre-filled)
    expect(page).to have_css("h2", text: "Departments & job roles")
    expect(find_field("Departments").value).to include("Engineering")
    fill_in "Job roles", with: "Software Engineer\nAccountant"
    click_button "Save & continue"

    # Finish
    expect(page).to have_text("Ready to go")
    click_link "Back"
    click_button "Save & continue"
    click_button "Finish setup"

    expect(page).to have_text("Setup complete")
    expect(page).to have_css("nav", text: "Acme Corporation")
    expect(organization.reload).to be_setup_completed
    expect(organization.country_allowances.pluck(:name)).to eq([ "HRA" ])

    # Resuming later skips the wizard
    visit onboarding_root_path
    expect(page).to have_current_path(authenticated_root_path)
  end

  it "rejects a wrong password with a generic message" do
    visit root_path
    fill_in "Email", with: "hr@acme.test"
    fill_in "Password", with: "wrong-password-123"
    click_button "Sign in"

    expect(page).to have_text("Invalid email or password.")
  end
end
