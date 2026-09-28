module Payroll
  # A pay month, e.g. September 2026: its first and last day, number of days and URL form ("2026-09").
  Month = Data.define(:start) do
    def self.parse(text)
      match = text.to_s.match(/\A(\d{4})-(\d{2})\z/)
      new(Date.new(match[1].to_i, match[2].to_i, 1)) if match && match[2].to_i.between?(1, 12)
    end

    def self.containing(date) = new(date.beginning_of_month)

    def finish = start.end_of_month
    def days = finish.day
    def range = start..finish
    def previous = Month.new(start.prev_month)
    def next = Month.new(start.next_month)
    def to_param = start.strftime("%Y-%m")
    def label = start.strftime("%B %Y")
    def to_s = label

    def <=>(other) = other.is_a?(Month) ? start <=> other.start : nil
    include Comparable

    # The days the employee was employed in this month (hire date .. last working day, clipped to the month), or nil.
    def employed_range(employee)
      from = [ employee.hire_date, start ].max
      to = [ employee.employment_end_date || finish, finish ].min
      from..to if from <= to
    end

    def days_employed(employee) = employed_range(employee)&.count.to_i
  end
end
