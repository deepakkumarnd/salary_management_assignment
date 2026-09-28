module Onboarding
  class CompletionsController < BaseController
    def create
      if wizard.finish!
        redirect_to authenticated_root_path, notice: "Setup complete. Welcome to Salary Management!"
      else
        redirect_to onboarding_step_path(wizard.incomplete_steps.first), alert: "A few steps still need an answer."
      end
    end
  end
end
