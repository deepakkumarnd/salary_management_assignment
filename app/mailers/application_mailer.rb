class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Salary Management <no-reply@salary-management.test>")
  layout "mailer"
end
