# frozen_string_literal: true

module Disposita
  module Internal
    # Sentinel distinguishing "no default declared" from an explicit nil default.
    # @api private
    UNDEFINED = Object.new.freeze

    # Immutable internal record describing one leaf setting in a schema.
    #
    # DSL input is normalized into this value object so resolution, validation,
    # introspection and persistence operate on one stable representation.
    #
    # @api private
    SettingDefinition = Data.define(
      :path,
      :type,
      :default,
      :required,
      :env,
      :secret,
      :description,
      :coerce,
      :validator
    ) do
      # @return [String] dotted setting path used in diagnostics.
      def key = path.join(".")

      # @return [Boolean] whether an explicit default was declared, including nil.
      def default? = !default.equal?(UNDEFINED)

      # @return [Boolean] whether diagnostics must redact this setting.
      def secret? = secret

      # @return [Boolean] whether the setting must exist after resolution.
      def required? = required

      # @return [Boolean] whether raw values may be coerced to the declared type.
      def coerce? = coerce
    end
  end
end
