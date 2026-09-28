FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    employee_code_prefix { "ACME" }
    standard_hours_per_week { 40 }
    setup_completed_at { Time.current }

    trait(:pending_setup) { setup_completed_at { nil } }
  end
end
