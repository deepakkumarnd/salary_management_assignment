# The payroll file for a country and month: choose (index, with the export log), check the summary and warnings (new),
# then download (create), which also logs who exported what, when, and the file's checksum.
class PayrollExportsController < AuthenticatedController
  before_action :load_choices
  before_action :set_run, only: %i[new create]

  def index
    @exports = Current.organization.payroll_exports.includes(:country, :exported_by).order(created_at: :desc).limit(25)
  end

  def new
  end

  def create
    export = Payroll::CsvExport.new(@run)
    csv = export.to_s
    Current.organization.payroll_exports.create!(country: @run.country, period_start: @run.month.start, exported_by: Current.user,
                                                 row_count: export.row_count, sha256: Digest::SHA256.hexdigest(csv))
    send_data csv, filename: export.filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  private

  # Months from the earliest hire up to next month (so scheduled changes can be previewed), newest first.
  def load_choices
    @countries = Current.organization.countries.order(:name)
    first_hire = Current.organization.employees.minimum(:hire_date) || Date.current
    @months = []
    month = Payroll::Month.containing(Date.current.next_month)
    while month.start >= first_hire.beginning_of_month
      @months << month
      month = month.previous
    end
    @current_month = Payroll::Month.containing(Date.current)
  end

  def set_run
    country = @countries.find(params[:country_id])
    month = Payroll::Month.parse(params[:month])
    return redirect_to(payroll_exports_path, alert: "Choose a month between #{@months.last.label} and #{@months.first.label}.") unless month.in?(@months)

    @run = Payroll::Run.new(Current.organization, country, month)
  end
end
