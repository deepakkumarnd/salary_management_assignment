require "rails_helper"

RSpec.describe "Home", type: :request do
  it "renders the landing page" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Salary Management")
  end
end
