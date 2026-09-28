module FormsHelper
  # daisyUI control classes, plus the error state when the attribute has errors.
  #   input_class(@organization, :name)                       → "input w-full" / "input w-full input-error"
  #   input_class(@catalogue, :departments, "textarea")       → "textarea w-full ..."
  def input_class(record, attribute, control = "input", *extra)
    class_names(control, "w-full", *extra, "#{control}-error" => record.errors.include?(attribute))
  end

  # Field-level error text below a control. full: false shows just the message ("Add at least one department").
  def field_errors(record, attribute, full: true)
    messages = full ? record.errors.full_messages_for(attribute) : record.errors.messages_for(attribute).map(&:upcase_first)
    tag.p(safe_join(messages, tag.br), class: "text-error text-sm mt-1") if messages.any?
  end
end
