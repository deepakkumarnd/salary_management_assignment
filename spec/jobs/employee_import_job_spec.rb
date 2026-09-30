require "rails_helper"

RSpec.describe EmployeeImportJob, type: :job do
  let(:organization) { create(:organization) }
  let(:import) do
    EmployeeImport.create!(organization:, uploaded_by: create(:user, organization:),
                           file: { io: StringIO.new("name\n"), filename: "people.csv", content_type: "text/csv" })
  end

  it "runs the import" do
    run = instance_double(EmployeeImports::Run, call: nil)
    allow(EmployeeImports::Run).to receive(:new).with(import).and_return(run)

    described_class.perform_now(import)

    expect(run).to have_received(:call)
  end

  it "does nothing for an import that already finished" do
    import.update!(status: "completed")
    allow(EmployeeImports::Run).to receive(:new)

    described_class.perform_now(import)

    expect(EmployeeImports::Run).not_to have_received(:new)
  end

  it "marks the import failed on an unexpected error, and still fails the job" do
    allow(EmployeeImports::Run).to receive(:new).and_raise(NoMethodError, "boom")

    expect { described_class.perform_now(import) }.to raise_error(NoMethodError)
    expect(import.reload).to have_attributes(status: "failed", finished_at: be_present)
    expect(import.error_message).to start_with("The import stopped unexpectedly.")
  end

  it "retries later while the database is busy" do
    allow(EmployeeImports::Run).to receive(:new).and_raise(ActiveRecord::StatementTimeout)

    expect { described_class.perform_now(import) }.to have_enqueued_job(described_class).with(import)
    expect(import.reload.status).to eq("queued")
  end

  it "runs one import at a time per organization" do
    job = described_class.new(import)
    expect(described_class.concurrency_limit).to eq(1)
    expect(job.concurrency_key).to end_with("/#{organization.id}")
  end
end
