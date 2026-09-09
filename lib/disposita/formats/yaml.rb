# frozen_string_literal: true

require "psych"

module Disposita
  # Serialization codecs used by file sources.
  # Supply a codec implementing load and dump through Sources::File.new.
  module Formats
    # Safe YAML codec used by the built-in file source.
    #
    # The codec deliberately accepts only ordinary data structures. Ruby object
    # deserialization, Symbol tags and YAML aliases are disabled, preventing a
    # configuration file from acting as an object-loading mechanism. Symbols in
    # runtime configuration are serialized as plain strings and restored later
    # by schema coercion when the declared type requires it.
    #
    # Quote values that YAML would otherwise interpret as special types when
    # they should be Strings. For example, +release_date: 2026-09-09+ is parsed
    # as a Date and rejected before schema coercion, even with +type: String+.
    # Write +release_date: "2026-09-09"+ instead. Date remains disallowed.
    #
    # Consumers normally interact with this module indirectly through
    # {Disposita::Sources::File}.
    module YAML
      module_function

      # Decodes safe YAML into a configuration Hash.
      #
      # @param content [String] YAML document.
      # @return [Hash] decoded mapping; an empty document becomes an empty Hash.
      # @raise [Disposita::ParseError] if YAML is malformed, contains unsafe
      #   constructs, or has a non-mapping document root.
      def load(content)
        data = Psych.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
        return {} if data.nil?
        raise ParseError, "configuration root must be a mapping" unless data.is_a?(Hash)

        data
      rescue Psych::Exception => e
        raise ParseError, "invalid YAML: #{e.message}"
      end

      # Encodes configuration data as safe, human-editable YAML.
      #
      # Hash keys and Symbols are converted to strings so emitted documents do
      # not depend on Ruby-specific YAML tags.
      #
      # @param data [Hash] validated configuration payload.
      # @return [String] YAML document.
      def dump(data)
        Psych.safe_dump(stringify(data), permitted_classes: [], permitted_symbols: [], aliases: false)
      end

      # @api private
      # Converts Ruby-oriented data to serialization-safe primitives.
      #
      # @param value [Object] nested configuration value.
      # @return [Object] equivalent value containing string keys/symbols.
      def stringify(value)
        case value
        when Hash
          value.to_h { |key, child| [key.to_s, stringify(child)] }
        when Array
          value.map { |child| stringify(child) }
        when Symbol
          value.to_s
        else
          value
        end
      end
      private_class_method :stringify
    end
  end
end
