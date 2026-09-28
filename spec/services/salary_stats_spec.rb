require "rails_helper"

RSpec.describe SalaryStats do
  it "gives count, min, max, average and median" do
    stats = described_class.new([ 300, 100, 200 ])

    expect(stats).to have_attributes(count: 3, min: 100, max: 300, average: 200, median: 200, total: 600)
  end

  it "takes the median of an even count as the mean of the middle two" do
    expect(described_class.new([ 400, 100, 300, 200 ]).median).to eq(250)
  end

  it "rounds averages and medians half up to whole units" do
    expect(described_class.new([ 1, 2 ]).average).to eq(2)          # 1.5 → 2
    expect(described_class.new([ 1, 2 ]).median).to eq(2)
    expect(described_class.new([ 1, 1, 2 ]).average).to eq(1)       # 1.33 → 1
  end

  it "is exact for large salaries" do
    values = [ 1_200_000, 1_200_001, 99_999_999 ]
    expect(described_class.new(values).average).to eq(34_133_333)   # 102,400,000 / 3 = 34,133,333.33
  end

  it "handles a single value" do
    expect(described_class.new([ 500 ])).to have_attributes(count: 1, min: 500, max: 500, average: 500, median: 500)
  end

  it "compares by value" do
    expect(described_class.new([ 1, 2 ])).to eq(described_class.new([ 2, 1 ]))
    expect(described_class.new([ 1, 2 ])).not_to eq(described_class.new([ 1, 3 ]))
  end

  it "has no figures for an empty set" do
    expect(described_class.new([])).to have_attributes(count: 0, min: nil, max: nil, average: nil, median: nil, total: 0)
    expect(described_class.new([])).to be_empty
  end
end
