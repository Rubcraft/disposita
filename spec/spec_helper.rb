# frozen_string_literal: true

# Shared RSpec and coverage setup for the Disposita test suite.
#
# Keep global helpers intentionally small so each spec file documents and owns
# the behavior it exercises instead of depending on hidden shared state.

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  skip "/spec/"
  minimum_coverage line: 95, branch: 90 if ENV["COVERAGE"] == "true"
end

require "disposita"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
