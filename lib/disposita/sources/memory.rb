# frozen_string_literal: true

module Disposita
  module Sources
    # Simple in-memory source for runtime overrides, tests and adapters.
    #
    # Keys are normalized to Symbols recursively when the source is created.
    # Because the source is read-only, it is ideal for command-line arguments or
    # values supplied programmatically at the highest-precedence layer.
    #
    # @example
    #   source = Disposita::Sources::Memory.new(
    #     { server: { port: 9292 } },
    #     name: :runtime
    #   )
    class Memory < Source
      # @param data [Hash] partial configuration layer.
      # @param name [String, Symbol] provenance name.
      def initialize(data, name: :memory)
        super(name: name)
        @data = Internal::HashTools.symbolize(data)
      end

      # @param _schema [Disposita::Schema] unused; included for Source contract.
      # @return [Hash] normalized in-memory layer.
      def read(_schema) = @data
    end
  end
end
