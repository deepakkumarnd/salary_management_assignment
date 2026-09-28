# A log entry for each downloaded payroll file: who, when, which country and month, how many rows, and the SHA-256 of
# the file as downloaded. The file itself isn't stored; re-opening a month warns if its data changed since the last one.
class PayrollExport < ApplicationRecord
  belongs_to :organization
  belongs_to :country
  belongs_to :exported_by, class_name: "User"

  def month = Payroll::Month.containing(period_start)
end
