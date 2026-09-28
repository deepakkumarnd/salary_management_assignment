# Percentages are stored as integer basis points (4000 = 40.00%) and edited as text ("40", "12.5").
#
#   percent_attribute :percent, column: :percent_bp, range: 1..20_000
#
# defines #percent ("40.00") and #percent= (parses, keeps the raw input for re-display) and validates the value
# on the virtual attribute, so error messages read "Percent must be ...".
module PercentAttribute
  extend ActiveSupport::Concern

  INPUT_FORMAT = /\A\d+(\.\d{1,2})?\z/

  def self.to_basis_points(value)
    text = value.to_s.strip.delete_suffix("%").strip
    (BigDecimal(text) * 100).to_i if text.match?(INPUT_FORMAT)
  end

  def self.format(basis_points, trim: false)
    text = Kernel.format("%.2f", basis_points / 100r)
    trim ? text.sub(/\.?0+\z/, "") : text
  end

  class_methods do
    def percent_attribute(name, column:, range:)
      input_ivar = :"@#{name}_input"

      define_method(name) do
        next instance_variable_get(input_ivar) if instance_variable_defined?(input_ivar)
        basis_points = public_send(column)
        PercentAttribute.format(basis_points) if basis_points
      end

      define_method(:"#{name}=") do |value|
        instance_variable_set(input_ivar, value)
        public_send(:"#{column}=", PercentAttribute.to_basis_points(value))
      end

      validate do
        basis_points = public_send(column)
        if basis_points.nil?
          input = instance_variable_get(input_ivar) if instance_variable_defined?(input_ivar)
          input.blank? ? errors.add(name, :blank) : errors.add(name, "must be a number with at most 2 decimal places")
        elsif !range.cover?(basis_points)
          errors.add(name, "must be between #{PercentAttribute.format(range.min, trim: true)} " \
                           "and #{PercentAttribute.format(range.max, trim: true)}")
        end
      end
    end
  end
end
