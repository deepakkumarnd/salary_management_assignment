FactoryBot.define do
  factory :payroll_deduction do
    employee
    organization { employee.organization }
    created_by   { association :user, organization: }
    period_start { Date.current.beginning_of_month }
    kind { "other" }
    amount { 5_000 }
    description { "Salary advance recovery" }

    trait :unpaid_leave do
      kind { "unpaid_leave" }
      unpaid_half_days { 2 }   # 1 day
      amount { nil }
      description { nil }
    end
  end

  factory :payroll_export do
    organization
    country
    period_start { Date.current.beginning_of_month.prev_month }
    row_count { 1 }
    sha256 { SecureRandom.hex(32) }
    exported_by { association :user, organization: }
  end
end
