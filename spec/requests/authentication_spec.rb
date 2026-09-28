require "rails_helper"

RSpec.describe "Authentication", type: :request do
  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, password:) }

  def sign_in_with(email, password)
    post user_session_path, params: { user: { email:, password: } }
  end

  describe "signed out" do
    it "redirects app pages to the sign-in page" do
      [ onboarding_root_path, edit_onboarding_organization_path, edit_onboarding_catalogue_path ].each do |path|
        get path
        expect(response).to redirect_to(new_user_session_path), "expected #{path} to require sign-in"
      end
    end

    it "shows the sign-in form at the root" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in")
    end
  end

  describe "signing in" do
    it "takes users of a set-up organization to the app" do
      sign_in_with(user.email, password)

      expect(response).to redirect_to(authenticated_root_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "takes users of an organization still being set up to the wizard" do
      user = create(:user, password:, organization: create(:organization, :pending_setup))

      sign_in_with(user.email, password)

      expect(response).to redirect_to(onboarding_root_path)
    end

    it "accepts the email in any case" do
      sign_in_with(user.email.upcase, password)
      expect(response).to redirect_to(authenticated_root_path)
    end

    it "gives the same generic error for a wrong password and an unknown email" do
      sign_in_with(user.email, "wrong-password-123")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password.")

      sign_in_with("nobody@example.test", password)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password.")
    end

    it "locks the account after 5 failed attempts and unlocks it after an hour" do
      5.times { sign_in_with(user.email, "wrong-password-123") }
      expect(user.reload).to be_access_locked

      sign_in_with(user.email, password)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password.")   # paranoid: doesn't reveal the lock

      travel 61.minutes do
        sign_in_with(user.email, password)
        expect(response).to redirect_to(authenticated_root_path)
      end
    end

    it "refuses a deactivated account with the generic message" do
      user.update!(deactivated_at: Time.current)

      sign_in_with(user.email, password)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Invalid email or password.")
    end
  end

  describe "an open session" do
    before { sign_in user }

    it "ends on the next request once the account is deactivated" do
      user.update!(deactivated_at: Time.current)

      get authenticated_root_path

      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(response.body).to include("Your account has been deactivated.")
    end

    it "times out after 30 minutes of inactivity" do
      get authenticated_root_path
      expect(response).to have_http_status(:ok)

      travel 31.minutes do
        get authenticated_root_path
        follow_redirect!   # Devise sends the user back to the page they asked for, now signed out

        expect(response.body).to include("Your session expired. Please sign in again to continue.", "Sign in")
        get onboarding_root_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "has no remember-me option" do
      sign_out user
      get new_user_session_path
      expect(response.body).not_to include("remember_me")
    end

    it "times out after 30 minutes even if the sign-in form asked to be remembered" do
      sign_out user
      post user_session_path, params: { user: { email: user.email, password:, remember_me: "1" } }
      expect(cookies[:remember_user_token]).to be_blank

      travel 31.minutes do
        get onboarding_root_path
        follow_redirect!   # Devise sends the user back to the page they asked for, now signed out

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "can be signed out" do
      delete destroy_user_session_path
      get onboarding_root_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "password reset" do
    it "emails a reset link to an active account" do
      expect { post user_password_path, params: { user: { email: user.email } } }
        .to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
    end

    it "sends nothing for an unknown email or a deactivated account, with the same response" do
      deactivated = create(:user, :deactivated)

      [ "nobody@example.test", deactivated.email ].each do |email|
        expect { post user_password_path, params: { user: { email: } } }
          .not_to change { ActionMailer::Base.deliveries.count }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "sign-up" do
    it "has no public sign-up route" do
      get "/users/sign_up"
      expect(response).to have_http_status(:not_found)

      post "/users", params: { user: { email: "new@example.test", password: } }
      expect(response).to have_http_status(:not_found)
    end
  end
end
