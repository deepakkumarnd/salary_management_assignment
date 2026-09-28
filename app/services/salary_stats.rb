# Min, max, average and median of whole-unit amounts. Averages and medians use exact Rational arithmetic and are
# rounded half up to whole units, like every other amount in the app. An empty set has a count of 0 and no figures.
class SalaryStats
  attr_reader :count, :min, :max, :average, :median

  def initialize(values)
    sorted = values.sort
    @count = sorted.size
    return if sorted.empty?

    @min = sorted.first
    @max = sorted.last
    @average = Rational(sorted.sum, count).round(half: :up)
    middle = count / 2
    @median = count.odd? ? sorted[middle] : Rational(sorted[middle - 1] + sorted[middle], 2).round(half: :up)
  end

  def empty? = count.zero?
end
