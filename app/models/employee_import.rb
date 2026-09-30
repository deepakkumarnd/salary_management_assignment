# An uploaded CSV of new employees, imported in the background by EmployeeImportJob (see EmployeeImports::Run).
# Tracks progress so the page can show it, and so a job that stops half-way resumes where it left off.
class EmployeeImport < ApplicationRecord
  MAX_FILE_SIZE = 200.megabytes   # about 1,000,000 rows
  MAX_ROWS = 1_000_000
  PARTIAL_HINT = "The rows counted as imported were created; uploading the same file again imports the rest " \
                 "(rows already imported are skipped because their emails are used)."

  belongs_to :organization
  belongs_to :uploaded_by, class_name: "User"
  has_one_attached :file
  has_many :skipped_rows, class_name: "EmployeeImportSkippedRow", dependent: :delete_all

  enum :status, { queued: "queued", processing: "processing", completed: "completed", failed: "failed" }, validate: true

  validate :file_is_a_csv, on: :create

  def finished? = completed? || failed?

  def filename = file.filename.to_s

  def percent_done
    return 100 if completed?
    return 0 if total_rows.to_i.zero?
    processed_rows * 100 / total_rows
  end

  def fail!(message)
    update!(status: "failed", error_message: message, finished_at: Time.current)
  end

  private

  def file_is_a_csv
    if !file.attached?
      errors.add(:file, "must be chosen")
    elsif file.filename.extension.downcase != "csv"
      errors.add(:file, "must be a .csv file (in Excel: Save As → CSV UTF-8)")
    elsif file.byte_size > MAX_FILE_SIZE
      errors.add(:file, "is too large: the limit is #{MAX_FILE_SIZE / 1.megabyte} MB")
    end
  end
end
