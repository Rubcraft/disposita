# frozen_string_literal: true

module Disposita
  module Internal
    # Evaluates the schema declaration DSL and records setting definitions.
    #
    # The builder is intentionally private. Public callers keep the immutable
    # {Disposita::Schema} returned by +Disposita.define_schema+ rather than retaining
    # mutable DSL state.
    #
    # @api private
    class SchemaBuilder
      # @return [Array<SettingDefinition>] definitions accumulated by this root
      #   builder and its nested namespace builders.
      attr_reader :settings

      # @param prefix [Array<Symbol>] namespace path for this builder.
      # @param settings [Array<SettingDefinition>] shared definition collection.
      def initialize(prefix: [], settings: [])
        @prefix = prefix
        @settings = settings
      end

      # Declares a nested namespace and evaluates its block in a child builder.
      #
      # @param name [String, Symbol] non-empty namespace segment without dots.
      # @yield nested schema DSL.
      # @return [Object] result of evaluating the namespace block.
      # @raise [SchemaError] when the name is invalid.
      def namespace(name, &)
        validate_name!(name)
        self.class.new(prefix: @prefix + [name.to_sym], settings: settings).instance_eval(&)
      end

      # Declares one leaf configuration setting.
      #
      # The validator block belongs to the consumer's schema semantics; Disposita
      # merely invokes it after type coercion. +optional+ currently exists to
      # make intent explicit and to detect contradictory declarations; absence is
      # otherwise optional unless +required: true+ is used.
      #
      # @param name [String, Symbol] non-empty setting segment without dots.
      # @param type [Object] Ruby class or type-like object understood by
      #   TypeAdapter.
      # @param default [Object] default value, copied and deeply frozen when
      #   declared; UNDEFINED when absent.
      # @param required [Boolean] whether resolution must produce the setting.
      # @param optional [Boolean] explicit optional marker.
      # @param env [String, nil] explicit environment variable name.
      # @param secret [Boolean] whether diagnostics must redact the value.
      # @param description [String, nil] user-facing documentation text.
      # @param coerce [Boolean] whether raw values may be coerced.
      # @yieldparam value [Object] coerced value for custom validation.
      # @yieldreturn [Boolean] truthy when the value is valid.
      # @raise [SchemaError] for contradictory or duplicate definitions.
      def setting(name, type:, default: UNDEFINED, required: false, optional: false,
                  env: nil, secret: false, description: nil, coerce: true, &validator)
        validate_name!(name)
        validate_presence!(required, optional)
        path = @prefix + [name.to_sym]
        reject_duplicate!(path)

        settings << SettingDefinition.new(
          path: path.freeze,
          type: type,
          default: immutable_default(default),
          required: required,
          env: env,
          secret: secret,
          description: description,
          coerce: coerce,
          validator: validator
        )
      end

      private

      def immutable_default(value)
        return UNDEFINED if value.equal?(UNDEFINED)

        HashTools.deep_freeze(HashTools.deep_dup(value))
      end

      def validate_presence!(required, optional)
        raise SchemaError, "required and optional cannot both be true" if required && optional
      end

      def reject_duplicate!(path)
        return unless settings.any? { |item| item.path == path }

        raise SchemaError, "duplicate setting: #{path.join('.')}"
      end

      def validate_name!(name)
        raise SchemaError, "names must be String or Symbol" unless name.is_a?(String) || name.is_a?(Symbol)
        return unless name.to_s.empty? || name.to_s.include?(".")

        raise SchemaError, "names must be non-empty path segments without dots"
      end
    end
  end
end
