# Seed Faker from RSpec's --seed so a failing run can be reproduced exactly.
RSpec.configure do |config|
  config.before(:suite) { Faker::Config.random = Random.new(config.seed) }
end
