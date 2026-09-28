# Pay policy: the organization's operating countries (index), and one country's allowances and pay structures (show).
class CountriesController < AuthenticatedController
  def index
    @countries = Current.organization.countries.order(:name)
    @allowance_counts = Current.organization.country_allowances.group(:country_id).count
    @structure_counts = Current.organization.pay_structures.group(:country_id).count
    @role_count = Current.organization.job_roles.count
  end

  def show
    @country = Current.organization.countries.find(params[:id])
    @allowances = Current.organization.country_allowances.where(country: @country).order(:name).to_a
    @structures = Current.organization.pay_structures.where(country: @country)
                         .includes(:job_role, :allowances).sort_by { it.job_role.name.downcase }
    @roles_without_structure = Current.organization.job_roles.where.not(id: @structures.map(&:job_role_id))
                                      .order(:name).pluck(:name)
  end
end
