# frozen_string_literal: true

SimpleCov.configure do
  enable_coverage :branch
  skip "/spec/"
  minimum_coverage line: 95, branch: 90
end
