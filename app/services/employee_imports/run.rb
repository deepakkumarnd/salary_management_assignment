require "csv"

module EmployeeImports
  # Imports an uploaded CSV of new employees (up to EmployeeImport::MAX_ROWS rows), for EmployeeImportJob:
  #
  #   EmployeeImports::Run.new(import).call
  #
  # The file is read one row at a time and written in batches of BATCH_SIZE with insert_all: each batch is one short
  # transaction (employees, their hire revisions, the skipped rows and the progress), so SQLite's single writer is
  # never held for long and the app stays usable during a large import. Progress is saved with the batch, so a job
  # that stops half-way resumes after the last saved batch without creating or skipping any row twice.
  #
  # insert_all skips the models' validations and callbacks, so this class upholds Employee's rules itself: Row checks
  # the values, and this class checks what needs the database. Rows are skipped, with every reason, when:
  # - the email was ever used by an employee of the organization (current or former), or earlier in the file;
  # - the country isn't one of the organization's operating countries;
  # - there's no pay structure for the designation in that country (HR creates it, then re-uploads those rows).
  # Departments and designations that don't exist yet are created, for rows that pass every other check.
  class Run
    BATCH_SIZE = 1_000
    HEADER = ->(header) { header.to_s.strip.downcase.gsub(/[\s-]+/, "_") }   # "Basic Pay" → "basic_pay"

    class FileError < StandardError; end

    def initialize(import, today: Date.current)
      @import = import
      @organization = import.organization
      @uploader = import.uploaded_by
      @today = today
    end

    def call
      @import.update!(status: "processing", started_at: @import.started_at || Time.current)
      @import.file.open do |file|
        @path = file.path
        count_rows if @import.total_rows.nil?
        load_lookups
        each_batch { process(it) }
      end
      @import.update!(status: "completed", finished_at: Time.current)
    rescue FileError => error
      @import.fail!(error.message)
    rescue CSV::MalformedCSVError => error
      @import.fail!("The file couldn't be read as CSV (#{error.message}). Save it as CSV UTF-8 and upload it again.")
    end

    private

    # --- reading the file ---------------------------------------------------------------------------------------

    # A full pass before anything is written, so a file with missing columns, too many rows or unreadable content
    # fails without creating anyone, and the page can show progress.
    def count_rows
      count = 0
      headers = read_rows do
        count += 1
        raise FileError, "The file has more than #{number(EmployeeImport::MAX_ROWS)} rows. Split it into smaller files." if count > EmployeeImport::MAX_ROWS
      end
      check_headers(headers)
      raise FileError, "The file has no employee rows below the column names." if count.zero?
      @import.update!(total_rows: count)
    end

    def check_headers(headers)
      raise FileError, "The file is empty." unless headers.is_a?(Array)

      missing = Row::REQUIRED_COLUMNS - headers
      return if missing.empty?
      raise FileError, "The file is missing the #{missing.to_sentence} #{"column".pluralize(missing.size)}. " \
                       "Its first row must be the column names: #{Row::COLUMNS.join(", ")} (the last two are optional)."
    end

    # Yields each non-blank row with its row number (as in a spreadsheet: the header is row 1); returns the headers.
    def read_rows
      File.open(@path, "r:bom|utf-8") do |file|
        csv = CSV.new(file, headers: true, header_converters: HEADER)
        csv.each { |fields| yield fields, csv.lineno unless fields.fields.all?(&:blank?) }
        csv.headers
      end
    end

    def each_batch
      already_done = @import.processed_rows
      batch = []
      read_rows do |fields, row_number|
        next if (already_done -= 1) >= 0   # resuming: these rows were saved by an earlier attempt

        batch << Row.from_csv(fields, row_number:, today: @today)
        if batch.size == BATCH_SIZE
          yield batch
          batch = []
        end
      end
      yield batch if batch.any?
    end

    # --- checks -------------------------------------------------------------------------------------------------

    # Names are matched ignoring case, like the NOCASE columns they're stored in.
    def load_lookups
      @countries = @organization.countries.index_by { it.name.downcase }
      @departments = @organization.departments.index_by { it.name.downcase }
      @job_roles = @organization.job_roles.index_by { it.name.downcase }
      @pay_structures = @organization.pay_structures.pluck(:country_id, :job_role_id).to_set
    end

    def process(rows)
      @missing = {}
      rows.each(&:validate)
      check_emails_not_used(rows)
      rows.each { check_country(it) }
      rows.each { resolve_role_and_department(it) if it.importable? }
      check_emails_unique_in_batch(rows)
      write(rows)
    end

    # One query per batch. Earlier batches are already saved, so this also catches repeats across the file.
    def check_emails_not_used(rows)
      emails = rows.map(&:email).compact_blank.uniq
      used = Employee.where(organization_id: @organization.id, email: emails).pluck(:email, :employee_code).to_h
      rows.each do |row|
        code = used[row.email]
        row.errors.add(:email, "is already used by employee #{code}") if code
      end
    end

    def check_country(row)
      return if row.country.blank?

      if (country = @countries[row.country.downcase])
        row.country_id = country.id
      elsif Country.where("name = ? COLLATE NOCASE", row.country).exists?
        row.errors.add(:country, "#{row.country} is not one of the organization's operating countries")
      else
        row.errors.add(:country, "#{row.country.inspect} is not a supported country")
      end
    end

    def resolve_role_and_department(row)
      row.department_id = find_or_create(:departments, row.department).id
      job_role = find_or_create(:job_roles, row.designation)
      row.job_role_id = job_role.id
      return if @pay_structures.include?([ row.country_id, row.job_role_id ])

      country = @countries[row.country.downcase]
      row.errors.add(:designation, "#{job_role.name} has no pay structure in #{country.name} yet. " \
                                   "Create one in Pay policy, then upload the skipped rows again.")
      missing = @missing[[ country.id, job_role.id ]] ||=
        { "country_id" => country.id, "country" => country.name, "job_role_id" => job_role.id, "job_role" => job_role.name, "rows" => 0 }
      missing["rows"] += 1
    end

    # A new department or job role is created on its own (a tiny write) and noted on the import at the same time.
    def find_or_create(association, name)
      cache = association == :departments ? @departments : @job_roles
      cache[name.downcase] ||= ActiveRecord::Base.transaction do
        scope = @organization.public_send(association)
        scope.find_by(name:) || scope.create!(name:).tap do |record|
          list = association == :departments ? :new_departments : :new_job_roles
          @import.update!(list => @import.public_send(list) + [ record.name ])
        end
      end
    end

    # The first row with an email wins; a later one in the same batch is skipped.
    def check_emails_unique_in_batch(rows)
      first_rows = {}
      rows.each do |row|
        next unless row.importable?

        if (first = first_rows[row.email])
          row.errors.add(:email, "is already used on row #{first} of this file")
        else
          first_rows[row.email] = row.row_number
        end
      end
    end

    # --- writing ------------------------------------------------------------------------------------------------

    def write(rows)
      skipped = ActiveRecord::Base.transaction do
        insert_importable(rows)
        skipped = rows.reject(&:importable?)
        created = rows.size - skipped.size
        insert_skipped(skipped)
        @import.update!(processed_rows: @import.processed_rows + rows.size,
                        created_count: @import.created_count + created,
                        skipped_count: @import.skipped_count + skipped.size,
                        missing_pay_structures: merged_missing_pay_structures)
        Organization.bump_pay_data_version(@organization.id) if created.positive?   # insert_all skips callbacks
        skipped
      end
      log(skipped)
    end

    # Someone may add an employee with one of these emails in the app meanwhile: the unique index then refuses the
    # whole batch, so it's retried one row at a time and only the clashing row is skipped.
    def insert_importable(rows)
      importable = rows.select(&:importable?)
      ActiveRecord::Base.transaction(requires_new: true) { insert_employees(importable) }
    rescue ActiveRecord::RecordNotUnique
      importable.each do |row|
        ActiveRecord::Base.transaction(requires_new: true) { insert_employees([ row ]) }
      rescue ActiveRecord::RecordNotUnique
        row.errors.add(:email, "was used by an employee added while this file was being imported")
      end
    end

    def insert_employees(rows)
      return if rows.empty?

      codes = EmployeeCode.reserve(@organization, rows.size).map { EmployeeCode.format_for(@organization, it) }
      employees = rows.zip(codes).map do |row, employee_code|
        { organization_id: @organization.id, employee_code:, full_name: row.name, email: row.email,
          country_id: row.country_id, job_role_id: row.job_role_id, department_id: row.department_id,
          employment_type: row.employment_type, hire_date: row.hire_date, updated_by_id: @uploader.id }
      end
      ids = Employee.insert_all!(employees, returning: %w[employee_code id]).rows.to_h

      revisions = rows.zip(codes).map do |row, code|
        { organization_id: @organization.id, employee_id: ids.fetch(code), effective_on: row.hire_date,
          basic_pay: row.basic_pay.to_i, reason: "hire", notes: "Imported from #{@import.filename}",
          created_by_id: @uploader.id }
      end
      SalaryRevision.insert_all!(revisions)
    end

    def insert_skipped(rows)
      return if rows.empty?

      EmployeeImportSkippedRow.insert_all!(rows.map do |row|
        { employee_import_id: @import.id, row_number: row.row_number, email: row.email.presence, data: row.data,
          reasons: row.errors.full_messages }
      end)
    end

    def merged_missing_pay_structures
      totals = @import.missing_pay_structures.index_by { [ it["country_id"], it["job_role_id"] ] }
      @missing.each do |key, missing|
        if totals[key] then totals[key] = totals[key].merge("rows" => totals[key]["rows"] + missing["rows"])
        else totals[key] = missing
        end
      end
      totals.values
    end

    def log(skipped)
      skipped.each do |row|
        Rails.logger.info "[EmployeeImport #{@import.id}] Skipped row #{row.row_number} (#{row.email.presence || "no email"}): " \
                          "#{row.errors.full_messages.join("; ")}"
      end
    end

    def number(count) = ActiveSupport::NumberHelper.number_to_delimited(count)
  end
end
