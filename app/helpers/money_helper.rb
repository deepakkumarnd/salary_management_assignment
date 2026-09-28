module MoneyHelper
  CURRENCY_UNITS = {
    "AUD" => "A$", "CAD" => "CA$", "EUR" => "€", "GBP" => "£", "INR" => "₹", "JPY" => "¥", "SGD" => "S$", "USD" => "$"
  }.freeze

  # Whole units of local currency: money(1_200_000, "INR") → "₹12,00,000"; money(65_000, "EUR") → "€65,000".
  # Indian rupees use lakh grouping, as HR in India writes them.
  def money(amount, currency_code)
    return "—" if amount.nil?

    digits = currency_code == "INR" ? indian_grouping(amount.abs) : number_with_delimiter(amount.abs)
    "#{'-' if amount.negative?}#{currency_unit(currency_code)}#{digits}"
  end

  # Value for an amount input: grouped like money ("12,00,000") when it's a saved number, or exactly what the user
  # typed when it didn't validate.
  def amount_input_value(record, attribute, currency_code)
    value = record.public_send(attribute)
    return record.read_attribute_before_type_cast(attribute) if value.nil? || record.errors.include?(attribute)
    money(value, currency_code).delete_prefix(currency_unit(currency_code))
  end

  def currency_unit(currency_code) = CURRENCY_UNITS.fetch(currency_code) { "#{currency_code} " }

  # 4000 → "40.00%"; with trim: 1500 → "15%"
  def percent(basis_points, trim: false) = "#{PercentAttribute.format(basis_points, trim:)}%"

  private

  def indian_grouping(number)
    head, last_three = number.to_s.then { [ it[0...-3], it[-3..] || it ] }
    return last_three if head.empty?
    "#{head.reverse.scan(/\d{1,2}/).join(',').reverse},#{last_three}"
  end
end
