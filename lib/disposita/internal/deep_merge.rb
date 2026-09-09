# frozen_string_literal: true

module Disposita
  # Implementation details shared by the public configuration API.
  #
  # Consumers should use Schema, Configuration and Source instead of coupling
  # integrations to these helpers, which may change without public API guarantees.
  # @api private
  module Internal
    # Implements Disposita's default layer merge semantics.
    #
    # Nested hashes are merged recursively so namespaces can be overridden one
    # setting at a time. Arrays and scalar values are replaced wholesale because
    # concatenating them would introduce domain-specific semantics the schema did
    # not explicitly request.
    #
    # @api private
    module DeepMerge
      module_function

      # @param left [Hash] higher-precedence values.
      # @param right [Hash] lower-precedence values.
      # @return [Hash] merged representation.
      def call(left, right)
        left.merge(right) do |_key, old_value, new_value|
          if old_value.is_a?(Hash) && new_value.is_a?(Hash)
            call(old_value, new_value)
          else
            old_value
          end
        end
      end
    end
  end
end
