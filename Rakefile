# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "yard"
require "yard/rake/yardoc_task"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--parallel"]
end

YARD::Rake::YardocTask.new(:yard) do |task|
  task.files = ["lib/**/*.rb"]
  task.options = ["--fail-on-warning"]
end

desc "Run the complete local CI suite"
task ci: %i[rubocop spec yard]

task default: :ci
