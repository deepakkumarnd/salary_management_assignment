require "rails_helper"

RSpec.describe "Home", type: :system do
  it "shows the landing page styled with daisyUI" do
    visit root_path

    expect(page).to have_css("h1.card-title", text: "Salary Management")
    expect(page).to have_css(".badge.badge-success", text: "Ready")
  end
end
