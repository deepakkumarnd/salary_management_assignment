require "rails_helper"

RSpec.describe "Edit conflicts", type: :system do
  let(:organization) { create(:organization) }
  let(:india) { create(:country, :india) }
  let(:colleague) { create(:user, organization:, full_name: "Priya Nair") }
  let!(:allowance) { create(:country_allowance, organization:, country: india, name: "HRA", percent_bp: 4_000) }

  before { sign_in create(:user, organization:) }   # the allowance factory makes India an operating country

  it "tells the user who changed the record and when, in their own time zone, and keeps their edit" do
    page.driver.browser.execute_cdp("Emulation.setTimezoneOverride", timezoneId: "Asia/Kolkata")

    visit edit_country_allowance_path(india, allowance)
    fill_in "Percent of basic", with: "50"

    travel_to Time.utc(2026, 9, 28, 9, 40) do
      Current.set(user: colleague) { CountryAllowance.find(allowance.id).update!(percent: "45") }
    end
    click_button "Save allowance"

    expect(page).to have_text("Priya Nair changed this allowance on 28 Sep 2026, 15:10")   # 09:40 UTC in India
    expect(page).to have_text("Saved value: 45.00")
    expect(page).to have_field("Percent of basic", with: "50")

    click_button "Save allowance"
    expect(page).to have_text("HRA was updated")
    expect(allowance.reload.percent_bp).to eq(5_000)
  end
end
