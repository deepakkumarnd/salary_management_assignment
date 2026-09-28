Rails.application.routes.draw do
  # HR users only: no public sign-up. Lockable unlocks by time, so there are no unlock-by-email pages either.
  devise_for :users, skip: %i[registrations unlocks]

  authenticated :user do
    root "employees#index", as: :authenticated_root
  end
  devise_scope(:user) { root "devise/sessions#new" }

  # Organization setup wizard, shown until setup is complete. GET /onboarding resumes at the current step.
  namespace :onboarding do
    root "steps#show"
    resource :organization, only: %i[edit update]
    resource :countries,    only: %i[edit update]
    resource :allowances,   only: %i[edit update]
    resource :catalogue,    only: %i[edit update]   # departments + job roles
    resource :completion,   only: :create
  end

  # Pay policy: the organization's operating countries, each with its allowances and role pay structures
  resources :countries, only: %i[index show] do
    resources :allowances, controller: "country_allowances", except: %i[index show]
  end
  resources :pay_structures, only: %i[new create edit update destroy] do
    get :preview, on: :collection                     # pay breakdown for forms (Turbo Frame)
  end

  # :id is the employee code (ACME-00042). Employees are never deleted.
  resources :employees, except: :destroy do
    resources :salary_revisions, only: %i[new create] do
      resource :void,       only: %i[new create], controller: "salary_revision_voids"
      resource :correction, only: %i[new create], controller: "salary_revision_corrections"
    end
    resource :employment_end, only: %i[new create destroy]   # destroy = undo exit
  end

  # Pay insights per operating country (current employees, as of today), with a role / department drill-down
  resources :insights, only: %i[index show], param: :country_id

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
