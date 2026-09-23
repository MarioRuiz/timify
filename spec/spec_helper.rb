# frozen_string_literal: true

if ENV["CI"] && ENV["COVERALLS_REPO_TOKEN"] && !ENV["COVERALLS_REPO_TOKEN"].empty?
  require "coveralls"
  Coveralls.wear!
else
  require "simplecov"
  SimpleCov.start
end

require "timify"
require "stringio"
require "logger"
require "json"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
