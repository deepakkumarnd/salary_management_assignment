# Imports an uploaded employee CSV (EmployeeImports::Run). One import at a time per organization, so two files can't
# race each other for the same emails. If the job stops half-way (a deploy, a crash, a busy database), running it
# again resumes after the last saved batch.
class EmployeeImportJob < ApplicationJob
  queue_as :default

  # Solid Queue holds the organization's slot until the job ends, or for at most the duration.
  limits_concurrency to: 1, key: ->(import) { import.organization_id }, duration: 2.hours

  rescue_from(StandardError) do |error|
    arguments.first.fail!("The import stopped unexpectedly. #{EmployeeImport::PARTIAL_HINT}")
    raise error   # still recorded as a failed job, with the backtrace
  end

  # SQLite busy for longer than the connection's timeout: try again later, carrying on where it stopped.
  retry_on ActiveRecord::StatementTimeout, wait: :polynomially_longer, attempts: 5 do |job, error|
    job.arguments.first.fail!("The database was too busy to finish the import. #{EmployeeImport::PARTIAL_HINT}")
    Rails.logger.error "[EmployeeImport #{job.arguments.first.id}] #{error.class}: #{error.message}"
  end

  def perform(import)
    return if import.finished?

    EmployeeImports::Run.new(import).call
  end
end
