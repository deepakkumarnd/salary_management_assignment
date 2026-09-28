FactoryBot.define do
  factory :country do
    sequence(:name) { |n| "#{Faker::Address.country} #{n}" }
    currency_code { Faker::Currency.code }

    trait(:india)   { name { "India" };   currency_code { "INR" } }
    trait(:germany) { name { "Germany" }; currency_code { "EUR" } }
  end
end
