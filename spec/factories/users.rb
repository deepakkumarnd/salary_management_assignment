FactoryBot.define do
  factory :user do
    organization
    full_name { Faker::Name.name }
    sequence(:email) { |n| "hr#{n}@example.test" }
    password { "correct-horse-battery" }

    trait :deactivated do
      deactivated_at { 1.day.ago }
    end
  end
end
