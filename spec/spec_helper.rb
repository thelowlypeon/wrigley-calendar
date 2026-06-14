# frozen_string_literal: true

require_relative "../lib/wrigley_calendar"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
end
