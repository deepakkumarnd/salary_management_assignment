# Don't wrap invalid fields in <div class="field_with_errors">: it breaks daisyUI layouts. Views add the
# error state themselves (FormsHelper#input_class / #field_errors).
Rails.application.config.action_view.field_error_proc = proc { |html_tag, _instance| html_tag }
