# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "yard"
require "yard/rake/yardoc_task"
require "rubygems/package"
require "tmpdir"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--parallel"]
end

YARD::Rake::YardocTask.new(:yard) do |task|
  task.files = ["lib/**/*.rb"]
  task.options = ["--fail-on-warning"]
end

desc "Check dependencies against the current advisory database"
task :audit do
  sh "bundle", "exec", "bundler-audit", "check", "--update"
end

desc "Generate public documentation from the built gem and reject internal API leakage"
task "yard:package" => :build do
  package = Gem::Package.new("pkg/disposita-#{Disposita::VERSION}.gem")
  Dir.mktmpdir("disposita-package-docs") do |directory|
    package.extract_files(directory)
    required = %w[.yardopts .yard/templates/default/module/setup.rb README.md]
    missing = required.reject { |file| File.file?(File.join(directory, file)) }
    abort "Missing packaged documentation files: #{missing.join(', ')}" unless missing.empty?

    sh Gem.ruby, Gem.bin_path("yard", "yardoc"), "--fail-on-warning", chdir: directory
    %w[class_list.html method_list.html Disposita/Configuration.html].each do |file|
      html = File.read(File.join(directory, "doc", file))
      if html.match?(%r{href=["'][^"']*(?:/Internal|/Node|/Types/(?:Boolean|Enum|ArrayOf))}) ||
         html.include?('id="method_missing_details"') || html.include?("#method_missing-instance_method")
        abort "Internal API leaked into packaged documentation: #{file}"
      end
    end
    puts "Packaged YARD documentation verified: configuration, template and private API filters."
  end
end

desc "Run the complete local CI suite"
task ci: %i[rubocop spec audit yard yard:package]

task default: :ci
