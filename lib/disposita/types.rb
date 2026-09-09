# frozen_string_literal: true

module Disposita
  # Configuration-oriented type helpers used by schema declarations.
  #
  # Disposita intentionally does not implement a general-purpose runtime type
  # system. Ruby classes such as +String+ and +Integer+ are accepted directly;
  # these helpers cover configuration-specific shapes that Ruby does not express
  # conveniently, such as booleans, finite enums and homogeneous arrays.
  #
  # Types participate in both validation and coercion. This matters especially
  # for environment variables, where every input starts as a String.
  #
  # @example
  #   Disposita.define_schema(:app) do
  #     setting :enabled, type: Disposita::Types.boolean, default: true
  #     setting :transport, type: Disposita::Types.enum(:ssh, :https)
  #     setting :hosts, type: Disposita::Types.array(String), default: []
  #   end
  module Types
    # Boolean configuration type supporting conventional textual forms.
    #
    # Resolved values are strictly +true+ or +false+. Coercion accepts common
    # ENV-friendly strings such as +"true"+, +"yes"+, +"1"+, +"false"+,
    # +"no"+ and +"0"+ case-insensitively.
    # @api private
    class Boolean
      # @param value [Object] candidate resolved value.
      # @return [Boolean] whether +value+ is exactly +true+ or +false+.
      def self.valid?(value) = [true, false].include?(value)

      # Coerces conventional string representations to a Ruby boolean.
      #
      # @param value [Object] raw configuration value.
      # @return [Boolean]
      # @raise [ArgumentError] when no unambiguous boolean conversion exists.
      def self.coerce(value)
        return value if valid?(value)
        return true if value.is_a?(String) && %w[true 1 yes on].include?(value.strip.downcase)
        return false if value.is_a?(String) && %w[false 0 no off].include?(value.strip.downcase)

        raise ArgumentError, "cannot coerce #{value.inspect} to boolean"
      end

      # @return [String] concise name used in schema diagnostics.
      def self.inspect = "Boolean"
    end

    # Type representing a finite set of accepted configuration values.
    #
    # String inputs may be coerced to Symbol members, which makes enums useful
    # for values arriving from ENV or YAML while preserving symbolic runtime
    # APIs.
    # @api private
    class Enum
      # @return [Array<Object>] allowed values.
      attr_reader :values

      # @param values [Array<Object>] finite non-empty set of allowed values.
      # @raise [ArgumentError] if the set is empty.
      def initialize(values)
        raise ArgumentError, "enum requires at least one value" if values.empty?

        @values = values.freeze
        freeze
      end

      # @param value [Object] candidate value.
      # @return [Boolean] whether +value+ belongs to the enum.
      def valid?(value) = values.include?(value)

      # Coerces a String to a matching Symbol member when possible.
      #
      # @param value [Object] raw configuration value.
      # @return [Object] matching enum member.
      # @raise [ArgumentError] when +value+ cannot match any allowed member.
      def coerce(value)
        return value if valid?(value)

        if value.is_a?(String)
          symbol = value.to_sym
          return symbol if values.include?(symbol)
          return value if values.include?(value)
        end

        raise ArgumentError, "expected one of #{values.map(&:inspect).join(', ')}"
      end

      # @return [String] human-readable representation used in diagnostics.
      def inspect = "enum(#{values.map(&:inspect).join(', ')})"
    end

    # Type representing an Array whose members share another declared type.
    #
    # Member types use the same adapter rules as top-level settings, so Ruby
    # classes and other Disposita type helpers can be nested.
    # @api private
    class ArrayOf
      # @return [Object] declared member type.
      attr_reader :member_type

      # @param member_type [Object] type expected for every array member.
      def initialize(member_type)
        @member_type = member_type
        freeze
      end

      # @param value [Object] candidate array.
      # @return [Boolean] whether +value+ is an Array and every member is valid.
      def valid?(value)
        value.is_a?(Array) && value.all? { |member| Internal::TypeAdapter.valid?(member_type, member) }
      end

      # Coerces every array member using the declared member type.
      #
      # @param value [Object] raw configuration value.
      # @return [Array] coerced members.
      # @raise [ArgumentError] if +value+ is not an Array or a member cannot be
      #   coerced.
      def coerce(value)
        raise ArgumentError, "expected Array" unless value.is_a?(Array)

        value.map { |member| Internal::TypeAdapter.coerce(member_type, member) }
      end

      # @return [String] human-readable representation used in diagnostics.
      def inspect = "Array[#{member_type.inspect}]"
    end

    module_function

    # Returns the built-in boolean type object.
    #
    # @return [Object] configuration type for use with +type:+.
    def boolean = Boolean

    # Builds a finite enum type.
    #
    # @param values [Array<Object>] accepted runtime values.
    # @return [Object] configuration type for use with +type:+.
    # @raise [ArgumentError] when no values are supplied.
    # @example
    #   type = Disposita::Types.enum(:ssh, :https)
    #   type.coerce("https") # => :https
    def enum(*values) = Enum.new(values)

    # Builds a homogeneous array type.
    #
    # @param member_type [Object] type required for every member.
    # @return [Object] configuration type for use with +type:+.
    # @example
    #   Disposita::Types.array(String)
    def array(member_type) = ArrayOf.new(member_type)
  end
end
