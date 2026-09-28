module Onboarding
  class CataloguesController < BaseController
    def edit
      @catalogue = CatalogueForm.new(Current.organization)
    end

    def update
      @catalogue = CatalogueForm.new(Current.organization, **catalogue_params.to_h.symbolize_keys)
      if @catalogue.save
        redirect_to onboarding_root_path
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def catalogue_params
      params.expect(onboarding_catalogue_form: %i[departments job_roles])
    end
  end
end
