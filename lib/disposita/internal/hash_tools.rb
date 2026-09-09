# frozen_string_literal: true

module Disposita
  module Internal
    # Recursive Hash helpers shared by schema resolution and immutable output.
    #
    # These operations deliberately work only with ordinary Ruby containers and
    # never use Marshal or object deserialization as a copying mechanism.
    #
    # @api private
    module HashTools
      module_function

      # Normalizes nested mapping keys to Symbols, including mappings inside arrays.
      # @param value [Object] raw tree.
      # @return [Object] normalized tree.
      def symbolize(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), result|
            result[key.to_sym] = symbolize(child)
          end
        when Array
          value.map { |child| symbolize(child) }
        else
          value
        end
      end

      # Reads a nested path without confusing an absent value with nil.
      # @param hash [Hash] tree to inspect.
      # @param path [Array<Symbol>] leaf path.
      # @return [Object] value or UNDEFINED when absent.
      def get(hash, path)
        path.reduce(hash) do |current, segment|
          return UNDEFINED unless current.is_a?(Hash) && current.key?(segment)

          current[segment]
        end
      end

      # Assigns a leaf value, creating intermediate namespace hashes as needed.
      # @param hash [Hash] tree to update.
      # @param path [Array<Symbol>] non-empty leaf path.
      # @param value [Object] value to assign.
      # @return [Hash] updated tree.
      def set(hash, path, value)
        cursor = hash
        path[0...-1].each { |segment| cursor = (cursor[segment] ||= {}) }
        cursor[path.last] = value
        hash
      end

      # Collects leaf paths for unknown-setting checks and provenance.
      # @param hash [Hash] tree to traverse.
      # @param prefix [Array<Symbol>] parent path.
      # @param result [Array<Array<Symbol>>] accumulator.
      # @return [Array<Array<Symbol>>] leaf paths.
      def flatten_keys(hash, prefix = [], result = [])
        hash.each do |key, value|
          path = prefix + [key.to_sym]
          value.is_a?(Hash) ? flatten_keys(value, path, result) : result << path
        end
        result
      end

      # Copies containers and values so exports do not mutate configuration.
      # @param value [Object] tree to copy.
      # @return [Object] detached copy, or original for non-duplicable values.
      def deep_dup(value)
        case value
        when Hash
          value.to_h { |key, child| [deep_dup(key), deep_dup(child)] }
        when Array
          value.map { |child| deep_dup(child) }
        else
          value.dup
        end
      rescue TypeError
        value
      end

      # Freezes a tree recursively, including mapping keys and array members.
      # @param value [Object] tree to freeze in place.
      # @return [Object] frozen tree.
      def deep_freeze(value)
        case value
        when Hash
          value.each do |key, child|
            deep_freeze(key)
            deep_freeze(child)
          end
        when Array
          value.each { |child| deep_freeze(child) }
        end
        value.freeze
      end
    end
  end
end
