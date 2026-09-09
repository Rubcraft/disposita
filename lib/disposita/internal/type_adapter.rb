# frozen_string_literal: true

module Disposita
  module Internal
    # Bridges Ruby classes and type-like objects used by Disposita schemas.
    #
    # The adapter intentionally defines a very small protocol: a custom type may
    # implement +valid?+ and optionally +coerce+. Otherwise normal Ruby case
    # equality (===) is used for validation and a small set of primitive
    # coercions is provided for configuration-friendly classes.
    #
    # Keeping this behind Internal lets Disposita later share or replace the type
    # machinery without making Typio or another Rubcraft gem a hard dependency.
    #
    # @api private
    module TypeAdapter
      module_function

      # @param type [Object] declared type.
      # @param value [Object] candidate value.
      # @return [Boolean] whether the value already satisfies the type.
      def valid?(type, value)
        return type.valid?(value) if type.respond_to?(:valid?)

        type === value # rubocop:disable Style/CaseEquality -- Ruby case equality is the supported type protocol.
      end

      # Coerces a raw configuration value to a declared type.
      #
      # @param type [Object] declared type.
      # @param value [Object] raw value.
      # @return [Object] coerced value.
      # @raise [CoercionError] when no safe conversion is available.
      def coerce(type, value)
        return value if valid?(type, value)
        return type.coerce(value) if type.respond_to?(:coerce)

        coerce_primitive(type, value)
      rescue ArgumentError, TypeError => e
        raise CoercionError, "cannot coerce #{value.inspect} to #{describe(type)}: #{e.message}"
      end

      # Converts built-in scalar types after custom protocols have been checked.
      # @param type [Object] declared type.
      # @param value [Object] raw value.
      # @return [Object] converted scalar.
      # @raise [ArgumentError, TypeError] when conversion is unavailable or invalid.
      def coerce_primitive(type, value)
        case type.respond_to?(:name) ? type.name : nil
        when "String"
          value.to_s
        when "Integer"
          Integer(value, 10)
        when "Float"
          Float(value)
        when "Symbol"
          value.is_a?(String) ? value.to_sym : raise(ArgumentError, "expected String")
        else
          raise ArgumentError, "no coercion available"
        end
      end

      # @param type [Object] declared type.
      # @return [String] human-readable type name for diagnostics.
      def describe(type)
        type.respond_to?(:name) && type.name ? type.name : type.inspect
      end
    end
  end
end
