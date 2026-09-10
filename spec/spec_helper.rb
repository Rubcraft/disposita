# frozen_string_literal: true

# Shared RSpec and coverage setup for the Disposita test suite.
#
# Keep global helpers intentionally small so each spec file documents and owns
# the behavior it exercises instead of depending on hidden shared state.

require "simplecov"

SimpleCov.start

require "disposita"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
