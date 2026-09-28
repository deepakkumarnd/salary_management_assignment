FactoryBot.define do
  factory :department do
    organization
    sequence(:name) { |n| "#{Faker::Commerce.department(max: 1)} #{n}" }
  end
end
