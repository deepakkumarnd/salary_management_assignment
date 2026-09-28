# For a 409 edit conflict (see AuthenticatedController#update_with_lock): @latest is what a colleague saved.
module ConflictsHelper
  # "Saved value: 45.00" under a field whose saved value differs from what the user is submitting.
  #   conflict_hint(@allowance, :percent, compare: :percent_bp)
  #   conflict_hint(@structure, :default_basic_pay) { money(it, currency) }
  def conflict_hint(record, attribute, compare: attribute)
    return unless @latest
    return if @latest.public_send(compare) == record.public_send(compare)

    saved = @latest.public_send(attribute)
    tag.p(class: "text-sm font-medium mt-1 flex items-center gap-2") do
      tag.span(class: "status status-warning", aria: { hidden: true }) + "Saved value: #{block_given? ? yield(saved) : saved}"
    end
  end
end
