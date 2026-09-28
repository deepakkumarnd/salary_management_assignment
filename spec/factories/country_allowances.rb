FactoryBot.define do
  factory :country_allowance do
    organization
    country
    sequence(:name) { |n| "Allowance #{n}" }
    percent_bp { 4_000 }

    after(:build) do |allowance|
      organization = allowance.organization
      organization.countries << allowance.country unless organization.countries.include?(allowance.country)
    end
  end
end
