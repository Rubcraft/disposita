# frozen_string_literal: true

module Disposita
  # Base contract for one configuration source/layer.
  #
  # A source contributes partial raw configuration data to a Schema. Sources are
  # intentionally small: they know how to read one layer and, optionally, how
  # to persist explicit data. Ordering and precedence remain the responsibility
  # of {Disposita::Schema#resolve}.
  #
  # Custom integrations can subclass Source to read from another system without
  # teaching Disposita about that system. A remote secret manager, database or
  # organization-specific store can therefore participate like any built-in
  # source.
  #
  # @example Implement a read-only custom source
  #   class DatabaseSource < Disposita::Source
  #     def read(_schema)
  #       { feature: { enabled: true } }
  #     end
  #   end
  #
  #   source = DatabaseSource.new(name: :database)
  #   config = schema.resolve([source])
  #
  # @see Disposita::Sources::Hash
  # @see Disposita::Sources::Environment
  # @see Disposita::Sources::File
  class Source
    # @return [Symbol] stable name used for provenance diagnostics.
    attr_reader :name

    # @param name [String, Symbol] source name reported by
    #   {Disposita::Configuration#source_of}.
    def initialize(name:)
      @name = name.to_sym
    end

    # Reads this source's partial configuration layer.
    #
    # Subclasses must implement this method and should return only raw scalar,
    # Array and Hash values. Schema coercion and validation happen later.
    #
    # @param _schema [Disposita::Schema] schema being resolved; custom sources
    #   may use it for introspection.
    # @return [Hash] partial configuration data.
    # @raise [NotImplementedError] in the base implementation.
    def read(_schema)
      raise NotImplementedError
    end

    # Indicates whether {#write} is supported.
    #
    # @return [Boolean] +false+ by default.
    def writable? = false

    # Indicates whether this source permits settings marked +secret: true+.
    #
    # Sources should default to the safer behavior and opt in only when their
    # storage characteristics are appropriate for secret material.
    #
    # @return [Boolean] +false+ by default.
    def allows_secrets? = false

    # Persists explicit validated data to this source.
    #
    # Subclasses that return +true+ from {#writable?} must implement this method.
    # Resolved configuration is never written implicitly; callers choose the
    # target source and payload through {Disposita::Schema#write}.
    #
    # @param _schema [Disposita::Schema] schema performing the write.
    # @param _data [Hash] validated partial payload including schema version.
    # @return [Object]
    # @raise [Disposita::SaveError] in the base implementation.
    def write(_schema, _data)
      raise SaveError, "source #{name.inspect} is read-only"
    end
  end
end
