FactoryBot.define do
  factory :pay_structure do
    organization
    job_role { association :job_role, organization: }
    country
    default_basic_pay       { Faker::Number.between(from: 30_000, to: 200_000) }
    variable_pay_percent_bp { 1_000 }
    overtime_percent_bp     { 15_000 }

    after(:build) do |structure|
      organization = structure.organization
      organization.countries << structure.country unless organization.countries.include?(structure.country)
    end
  end

  factory :pay_structure_allowance do
    pay_structure
    sequence(:name) { |n| "Role allowance #{n}" }
    percent_bp { 1_500 }
  end
end
