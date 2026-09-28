# Pay insights: current employees' basic, gross and total target pay per operating country, in its own currency
# (averaging across currencies would be meaningless), with a drill-down by job role and department.
class InsightsController < AuthenticatedController
  def index
    @reports = Current.organization.countries.order(:name).map { Insights::CountryReport.new(Current.organization, it) }
  end

  def show
    country = Current.organization.countries.find(params[:country_id])
    @report = Insights::CountryReport.new(Current.organization, country)
  end
end
