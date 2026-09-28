namespace :demo do
  desc 'Fill an organization with demo data at scale: bin/rails demo:populate ORG="ACME" EMPLOYEES=10000'
  task populate: :environment do
    name = ENV.fetch("ORG", "ACME")
    organization = Organization.find_by(name:) or abort "No organization named #{name.inspect}. Run bin/rails db:seed first."
    count = Integer(ENV.fetch("EMPLOYEES", "10000"))

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Demo::Populate.new(organization, employees: count).call
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    puts "Added #{count} employees to #{organization.name} in #{seconds.round(1)}s " \
         "(#{organization.employees.count} in total, #{organization.salary_revisions.count} salary revisions)."
  end
end
