FactoryBot.define do
  factory :job_role do
    organization
    sequence(:name) { |n| "#{Faker::Job.title} #{n}" }
  end
end
