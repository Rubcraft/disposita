# frozen_string_literal: true

module Disposita
  # Immutable, typed configuration produced after all sources are resolved.
  #
  # Configuration is the object an application normally consumes at runtime.
  # Values can be accessed through dot notation or brackets, but mutation is
  # intentionally unsupported. {#to_h} returns a detached copy when a mutable
  # representation is needed for interoperability.
  #
  # Every selected value retains provenance, allowing diagnostic tooling to
  # explain whether it came from a default, global file, project file, ENV or a
  # runtime override. Settings marked +secret: true+ are redacted from
  # diagnostic representations such as {#inspect} and {#explain}.
  #
  # @example
  #   schema = Disposita.define_schema(:app) do
  #     namespace(:server) { setting :port, type: Integer, default: 3000 }
  #   end
  #   config = schema.resolve
  #   config.server.port          # => 3000
  #   config[:server][:port]      # => 3000
  #   config.source_of("server.port") # => :default
  #
  # @see Disposita::Schema#resolve
  class Configuration
    # Read-only namespace node used to provide ergonomic nested access.
    #
    # Node deliberately wraps hashes instead of exposing them directly so the
    # resolved configuration remains immutable and secret-aware diagnostics can
    # be delegated back to the owning Configuration.
    # @api private
    class Node
      # @param data [Hash] subtree represented by this node.
      # @param root [Disposita::Configuration] owning root configuration.
      # @param path [Array<Symbol>] absolute path represented by this node.
      def initialize(data, root:, path: [])
        @data = data
        @root = root
        @path = path
        freeze
      end

      # Reads a child setting or namespace by key.
      #
      # @param key [String, Symbol] immediate child name.
      # @return [Object] scalar value or nested
      #   read-only node.
      # @raise [KeyError] when the child is not present in the resolved data.
      def [](key)
        value_for(key)
      end

      # Returns a detached mutable Hash representation of this subtree.
      #
      # Changing the returned object never mutates the resolved configuration.
      # This method returns actual secret values and should therefore not be
      # treated as a safe logging representation.
      #
      # @return [Hash]
      def to_h
        Internal::HashTools.deep_dup(@data)
      end

      # Returns a secret-aware diagnostic representation.
      #
      # @return [String] representation with secret settings replaced by
      #   +[REDACTED]+.
      def inspect
        @root.__send__(:inspect_node, @data, @path)
      end

      # Resolves dot access to a setting or namespace; unknown calls use Ruby lookup.
      # @param name [Symbol] requested setting name.
      # @param arguments [Array<Object>] arguments supplied by the caller.
      # @return [Object] resolved setting or namespace.
      # @raise [NoMethodError] for unknown names or calls with arguments.
      # @api private
      def method_missing(name, *arguments)
        return super unless arguments.empty? && @data.key?(name)

        value_for(name)
      end

      # @api private
      def respond_to_missing?(name, include_private = false)
        @data.key?(name) || super
      end

      private

      def value_for(key)
        key = key.to_sym
        raise KeyError, "unknown configuration key: #{(@path + [key]).join('.')}" unless @data.key?(key)

        value = @data[key]
        value.is_a?(Hash) ? self.class.new(value, root: @root, path: @path + [key]) : value
      end
    end

    # @return [Disposita::Schema] schema that produced this configuration.
    attr_reader :schema

    # Builds an immutable resolved configuration.
    # @api private
    #
    # Applications normally receive instances from {Disposita::Schema#resolve}
    # rather than constructing them directly.
    #
    # @param schema [Disposita::Schema] owning schema.
    # @param data [Hash] fully coerced and validated values.
    # @param provenance [Hash{Array<Symbol> => Symbol}] selected source for each
    #   resolved leaf setting.
    def initialize(schema:, data:, provenance:)
      @schema = schema
      @data = Internal::HashTools.deep_freeze(data)
      @provenance = provenance.freeze
      @root = Node.new(@data, root: self)
      freeze
    end

    # Reads a top-level setting or namespace.
    #
    # @param key [String, Symbol] top-level key.
    # @return [Object]
    # @raise [KeyError] when the key is absent.
    def [](key) = @root[key]

    # Reports which source supplied the effective value for a setting.
    #
    # @param path [String, Array<String, Symbol>, Symbol] setting path.
    # @return [Symbol, nil] source name, +:default+ for schema defaults, or +nil+
    #   when no provenance entry exists.
    def source_of(path)
      @provenance[normalize_path(path)]
    end

    # Explains one effective setting without exposing secret values.
    #
    # This small stable structure is intended for diagnostics and CLI commands
    # such as +config explain+. A secret setting reports +[REDACTED]+ even though
    # direct application access still returns its real value.
    #
    # @param path [String, Array<String, Symbol>, Symbol] setting path.
    # @return [Hash] frozen Hash containing +:path+, +:value+ and +:source+.
    # @raise [KeyError] if the path is not declared by the schema.
    def explain(path)
      normalized = normalize_path(path)
      setting = schema.describe(normalized)
      raise KeyError, "unknown configuration key: #{normalized.join('.')}" unless setting

      {
        path: normalized.join("."),
        value: setting[:secret] ? "[REDACTED]" : Internal::HashTools.deep_dup(@data.dig(*normalized)),
        source: @provenance[normalized]
      }.freeze
    end

    # Returns a detached mutable Hash containing resolved values.
    #
    # Unlike {#inspect}, this is a data export API and therefore includes actual
    # secret values. Callers are responsible for avoiding accidental logging or
    # persistence of the returned Hash.
    #
    # @return [Hash]
    def to_h
      Internal::HashTools.deep_dup(@data)
    end

    # Returns a secret-aware diagnostic representation of the configuration.
    #
    # @return [String]
    def inspect = inspect_node(@data, [])

    # Resolves dot access to a setting or namespace; unknown calls use Ruby lookup.
    # @param name [Symbol] requested setting name.
    # @param arguments [Array<Object>] arguments supplied by the caller.
    # @return [Object] resolved setting or namespace.
    # @raise [NoMethodError] for unknown names or calls with arguments.
    # @api private
    def method_missing(name, *arguments)
      return super unless arguments.empty? && @root.respond_to?(name)

      @root.public_send(name)
    end

    # @api private
    def respond_to_missing?(name, include_private = false)
      @root.respond_to?(name) || super
    end

    private

    def normalize_path(path)
      case path
      when String then path.split(".").map!(&:to_sym)
      when Array then path.map(&:to_sym)
      else Array(path).map!(&:to_sym)
      end
    end

    def inspect_node(data, prefix)
      body = data.map do |key, value|
        path = prefix + [key]
        setting = schema.describe(path)
        rendered = if setting && setting[:secret]
                     "[REDACTED]"
                   elsif value.is_a?(Hash)
                     inspect_node(value, path)
                   else
                     value.inspect
                   end
        "#{key}=#{rendered}"
      end.join(" ")
      "#<#{self.class.name} #{body}>"
    end
  end
end
