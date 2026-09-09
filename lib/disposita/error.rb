# frozen_string_literal: true

module Disposita
  # Base class for errors raised by Disposita.
  #
  # Consumers may rescue this class when they want one boundary around all
  # configuration failures, or rescue a narrower subclass to render specific
  # diagnostics in a CLI or application.
  class Error < StandardError; end

  # Raised when the consumer declares an invalid schema.
  class SchemaError < Error; end

  # Base class for failures discovered while validating configuration values.
  class ValidationError < Error; end

  # Raised when a raw value cannot be converted to its declared schema type.
  class CoercionError < ValidationError; end

  # Raised when a required setting remains absent after all layers are resolved.
  class MissingSettingError < ValidationError; end

  # Raised when a source contains a setting not declared by the schema.
  class UnknownSettingError < ValidationError; end

  # Raised when serialized configuration cannot be decoded safely.
  class ParseError < Error; end

  # Raised when a source cannot provide its configuration data.
  class LoadError < Error; end

  # Raised when configuration cannot be persisted to the requested source.
  class SaveError < Error; end

  # Raised when persisted configuration is newer than the runtime schema.
  class VersionError < Error; end

  # Raised when a conventional or project path cannot be resolved safely.
  class PathError < Error; end

  # Raised when secret data would be written to a source that forbids secrets.
  #
  # This protects against accidental persistence only. It does not imply that a
  # source allowing secrets provides encryption or a secret-management system.
  class UnsafeSecretPersistenceError < SaveError; end
end
