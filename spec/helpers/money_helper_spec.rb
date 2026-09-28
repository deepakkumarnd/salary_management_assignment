require "rails_helper"

RSpec.describe MoneyHelper, type: :helper do
  describe "#money" do
    it "groups rupees in lakhs and crores" do
      expect(helper.money(999, "INR")).to eq("₹999")
      expect(helper.money(1_200_000, "INR")).to eq("₹12,00,000")
      expect(helper.money(123_456_789, "INR")).to eq("₹12,34,56,789")
    end

    it "groups other currencies in thousands" do
      expect(helper.money(65_000, "EUR")).to eq("€65,000")
      expect(helper.money(1_200_000, "USD")).to eq("$1,200,000")
    end

    it "shows negatives and unknown currencies" do
      expect(helper.money(-1_500, "INR")).to eq("-₹1,500")
      expect(helper.money(10, "CHF")).to eq("CHF 10")
      expect(helper.money(nil, "INR")).to eq("—")
    end
  end

  describe "#amount_input_value" do
    it "groups a saved amount and keeps an invalid input as typed" do
      structure = build(:pay_structure, default_basic_pay: 1_200_000)
      expect(helper.amount_input_value(structure, :default_basic_pay, "INR")).to eq("12,00,000")

      structure.default_basic_pay = "12.5"
      structure.validate
      expect(helper.amount_input_value(structure, :default_basic_pay, "INR")).to eq("12.5")
    end
  end
end
