module Onboarding
  class CompletionsController < BaseController
    def create
      if wizard.finish!
        redirect_to countries_path,
                    notice: "Setup complete. Next, create a pay structure for each job role in each country."
      else
        redirect_to onboarding_step_path(wizard.incomplete_steps.first), alert: "A few steps still need an answer."
      end
    end
  end
end
