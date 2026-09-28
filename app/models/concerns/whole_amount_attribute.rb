# Money is stored as whole units of local currency. Forms accept thousands separators in any local style
# ("12,00,000", "1,200,000", "65 000") instead of silently reading "1,200,000" as 1.
#
#   whole_amount_attribute :default_basic_pay
#   whole_amount_attribute :initial_basic_pay, on: :create
module WholeAmountAttribute
  extend ActiveSupport::Concern

  MAXIMUM = 10**12   # far above any annual salary, well inside SQLite's 64-bit integers

  class_methods do
    def whole_amount_attribute(*names, **validation_options)
      names.each do |name|
        define_method(:"#{name}=") do |value|
          super(value.is_a?(String) ? value.gsub(/[\s,_]/, "") : value)
        end
      end
      validates(*names, numericality: { only_integer: true, greater_than: 0, less_than: MAXIMUM }, **validation_options)
    end
  end
end
