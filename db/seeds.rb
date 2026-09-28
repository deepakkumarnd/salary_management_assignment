# Idempotent: safe to re-run. Creates the global countries, the ACME organization (setup left pending, so the first
# sign-in goes through the setup wizard) and its first HR user. The password comes from SEED_HR_PASSWORD, or is
# generated and printed once. No password is committed to the repository.

COUNTRIES = {
  "Australia" => "AUD", "Canada" => "CAD", "Germany" => "EUR", "India" => "INR",
  "Japan" => "JPY", "Singapore" => "SGD", "United Kingdom" => "GBP", "United States" => "USD"
}.freeze

COUNTRIES.each do |name, currency_code|
  Country.find_or_create_by!(name:) { it.currency_code = currency_code }
end

HR_EMAIL = "hr@acme.test"

if User.active.exists?(email: HR_EMAIL)
  puts "HR user #{HR_EMAIL} already exists; nothing to do."
else
  acme = Organization.find_or_create_by!(name: "ACME") { it.employee_code_prefix = "ACME" }
  password = ENV["SEED_HR_PASSWORD"].presence || SecureRandom.base58(16)
  User.create!(organization: acme, full_name: "ACME HR", email: HR_EMAIL, password:)

  puts "Created HR user for #{acme.name}. Sign in at http://localhost:3000"
  puts "  email:    #{HR_EMAIL}"
  puts "  password: #{ENV['SEED_HR_PASSWORD'].present? ? '(from SEED_HR_PASSWORD)' : password}"
end
