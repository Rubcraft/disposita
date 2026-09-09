# frozen_string_literal: true

require_relative "disposita/version"
require_relative "disposita/error"
require_relative "disposita/internal/definition"
require_relative "disposita/internal/type_adapter"
require_relative "disposita/internal/schema_builder"
require_relative "disposita/internal/deep_merge"
require_relative "disposita/internal/hash_tools"
require_relative "disposita/types"
require_relative "disposita/source"
require_relative "disposita/formats/yaml"
require_relative "disposita/sources/hash"
require_relative "disposita/sources/environment"
require_relative "disposita/sources/file"
require_relative "disposita/paths"
require_relative "disposita/configuration"
require_relative "disposita/schema"

# Declarative, typed and layered configuration infrastructure for Ruby.
#
# Disposita lets a library or application own the meaning of its settings while
# delegating schema definition, coercion, validation, source precedence and
# persistence to a reusable configuration engine. Defining a schema does not
# read files, inspect ENV or mutate global state; consumers explicitly choose
# which sources participate when configuration is resolved.
#
# @example Define and resolve a small schema
#   AppConfig = Disposita.define(:app, version: 1) do
#     namespace :server do
#       setting :host, type: String, default: "localhost"
#       setting :port, type: Integer, default: 3000
#     end
#   end
#
#   config = AppConfig.resolve([])
#   config.server.host # => "localhost"
#   config.server.port # => 3000
#
# @example Combine a file layer with environment overrides
#   schema.load(
#     sources: [Disposita::Sources::File.new(".app.yml", name: :project)],
#     env: ENV,
#     env_prefix: "APP"
#   )
#
# @see Disposita::Schema
# @see Disposita::Configuration
# @see Disposita::Source
module Disposita
  module_function

  # Defines an independent configuration schema owned by the caller.
  #
  # The block is evaluated by Disposita's schema DSL. A schema is only a
  # description until the caller explicitly resolves it against one or more
  # sources, so this method is safe to use while loading a gem or application.
  #
  # @param name [String, Symbol] stable logical name of the consumer-owned
  #   configuration domain.
  # @param version [Integer] version of the persisted schema format. Versioning
  #   belongs to the consumer and is independent from Disposita's gem version.
  # @yield DSL used to declare namespaces and settings.
  # @return [Disposita::Schema] immutable schema that can be resolved, inspected
  #   and used to validate writes.
  # @raise [Disposita::SchemaError] if no block is supplied or the DSL contains
  #   an invalid schema definition.
  #
  # @example
  #   SCMConfig = Disposita.define(:scm, version: 1) do
  #     namespace :git do
  #       setting :remote, type: String, default: "origin"
  #       setting :transport,
  #               type: Disposita::Types.enum(:ssh, :https),
  #               default: :ssh
  #     end
  #   end
  def define(name, version: 1, &block)
    raise SchemaError, "a schema block is required" unless block

    builder = Internal::SchemaBuilder.new
    builder.instance_eval(&block)
    Schema.new(name: name, version: version, settings: builder.settings)
  end
end
