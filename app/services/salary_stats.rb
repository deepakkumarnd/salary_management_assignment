# Min, max, average, median and total of whole-unit amounts. Averages and medians use exact Rational arithmetic and are
# rounded half up to whole units, like every other amount in the app. An empty set has a count of 0 and no figures.
class SalaryStats
  attr_reader :count, :min, :max, :average, :median, :total

  def initialize(values)
    sorted = values.sort
    @count = sorted.size
    @total = sorted.sum
    return if sorted.empty?

    @min = sorted.first
    @max = sorted.last
    @average = Rational(total, count).round(half: :up)
    middle = count / 2
    @median = count.odd? ? sorted[middle] : Rational(sorted[middle - 1] + sorted[middle], 2).round(half: :up)
  end

  def empty? = count.zero?

  def to_h = { count:, min:, max:, average:, median:, total: }

  # A value: two stats with the same figures are equal (e.g. a cached report and a freshly computed one).
  def ==(other) = other.is_a?(SalaryStats) && to_h == other.to_h
  alias eql? ==
  def hash = to_h.hash
end
