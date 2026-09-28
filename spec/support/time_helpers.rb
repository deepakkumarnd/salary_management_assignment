# travel_to / freeze_time, so "today", status and default months are deterministic.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::TimeHelpers
end
