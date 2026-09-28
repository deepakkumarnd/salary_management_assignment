require "rails_helper"

RSpec.describe "Home", type: :request do
  it "welcomes a signed-in user of a set-up organization" do
    user = create(:user, full_name: "Priya Nair", organization: create(:organization, name: "Acme Corp"))
    sign_in user

    get authenticated_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acme Corp", "Priya Nair")
  end
end
