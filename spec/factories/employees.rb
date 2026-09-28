FactoryBot.define do
  factory :employee do
    pay_structure                                   # keeps organization, country and role consistent
    organization { pay_structure.organization }
    country      { pay_structure.country }
    job_role     { pay_structure.job_role }
    department   { association :department, organization: }
    recorded_by  { association :user, organization: }   # author of the hire revision
    full_name       { Faker::Name.name }
    sequence(:email) { |n| "employee#{n}@acme.test" }
    employment_type { "full_time" }
    hire_date       { Faker::Date.backward(days: 3650) }
    initial_basic_pay { pay_structure.default_basic_pay }   # becomes the hire revision

    trait :leaving do
      employment_end_date { 1.month.from_now.to_date }
      exit_reason { "resignation" }
    end

    trait :exited do
      hire_date { 2.years.ago.to_date }
      employment_end_date { 1.month.ago.to_date }
      exit_reason { "resignation" }
    end
  end

  factory :salary_revision do
    employee
    organization { employee.organization }
    created_by   { association :user, organization: }
    effective_on { employee.hire_date + 1.year }
    basic_pay    { 100_000 }
    reason       { "appraisal" }
  end
end
