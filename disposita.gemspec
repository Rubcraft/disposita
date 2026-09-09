# frozen_string_literal: true

require_relative "lib/disposita/version"

Gem::Specification.new do |spec|
  spec.name = "disposita"
  spec.version = Disposita::VERSION
  spec.authors = ["Rubcraft"]
  spec.summary = "Declarative, typed and layered configuration for Ruby"
  spec.description = <<~DESCRIPTION
    Disposita provides consumer-owned configuration schemas, typed values,
    coercion, validation, layered resolution, safe YAML persistence,
    environment overrides, cross-platform paths and secret-aware diagnostics.
  DESCRIPTION
  spec.homepage = "https://github.com/Rubcraft/disposita"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  end
  spec.require_paths = ["lib"]
end
