module Onboarding
  class StepsController < BaseController
    # Resumes at the current step, or shows the summary with "Finish setup".
    def show
      step = wizard.current_step
      return redirect_to(onboarding_step_path(step)) unless step == :finish

      @organization = Current.organization
      render :finish
    end
  end
end
