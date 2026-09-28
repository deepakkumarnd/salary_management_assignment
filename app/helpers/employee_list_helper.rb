# Links for the employee list. Each keeps the current search (EmployeeSearch#to_params), so sorting, paging and
# removing one filter never lose the others.
module EmployeeListHelper
  # A column header that sorts by the column; clicking the current sort column flips its direction.
  def sort_link(search, column, label, align: nil)
    current = search.sort == column
    dir = current && search.dir == "asc" ? "desc" : "asc"
    params = search.to_params.merge(sort: column, dir:)
    params.delete(:sort) if column == EmployeeSearch::DEFAULT_SORT
    params.delete(:dir) if dir == "asc"
    arrow = current ? (search.dir == "asc" ? " ▲" : " ▼") : ""

    link_to "#{label}#{arrow}", employees_path(params),
            class: class_names("link link-hover whitespace-nowrap", "text-base-content" => current, "justify-end" => align == :right),
            aria: { sort: current ? (search.dir == "asc" ? "ascending" : "descending") : nil }
  end

  # The list without one filter (a badge's ✕).
  def without_filter_path(search, key) = employees_path(search.to_params.except(key))

  # "1–25 of 1,243"
  def result_range(pagy)
    return "0 results" if pagy.count.zero?
    return "No results on this page (#{number_with_delimiter(pagy.count)} in total)" if pagy.from.zero?
    "#{number_with_delimiter(pagy.from)}–#{number_with_delimiter(pagy.to)} of #{number_with_delimiter(pagy.count)}"
  end

  # "No employees match “priya” in India · Software Engineer"
  def empty_result_message(search)
    filters = search.active_filters
    term = filters.find { it[:key] == :q }&.dig(:label)
    others = filters.reject { it[:key] == :q }.map { it[:label] }
    message = +"No employees match"
    message << (term ? " #{term}" : " these filters")
    message << " in #{others.join(' · ')}" if term && others.any?
    message << ": #{others.join(' · ')}" if !term && others.any?
    message
  end

  # Page numbers around the current page, with :gap for skipped ranges: [1, :gap, 7, 8, 9, :gap, 40]
  def page_series(pagy, around: 2)
    pages = ([ 1, pagy.last ] + ((pagy.page - around)..(pagy.page + around)).to_a)
              .select { it.between?(1, pagy.last) }.uniq.sort
    pages.each_cons(2).with_object([ pages.first ]) do |(previous, page), series|
      series << :gap if page > previous + 1
      series << page
    end
  end
end
