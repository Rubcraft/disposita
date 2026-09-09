# frozen_string_literal: true

module Disposita
  # Describes a consumer-owned configuration domain and resolves its values.
  #
  # A Schema contains structure and rules, not application semantics. It knows
  # that a setting is an Integer, required, secret or sourced from a particular
  # environment variable; the consumer remains responsible for deciding what
  # that value means to the application.
  #
  # Schemas are immutable after construction. Resolution is explicit and
  # ordered: sources are listed from highest to lowest precedence. Defaults are
  # the final fallback. Environment and runtime values are explicit sources.
  #
  # @example Resolve ordered layers
  #   schema = Disposita.define_schema(:app) do
  #     setting :port, type: Integer, default: 3000
  #   end
  #
  #   global  = Disposita::Sources::Memory.new({ port: 4000 }, name: :global)
  #   project = Disposita::Sources::Memory.new({ port: 5000 }, name: :project)
  #
  #   schema.resolve(sources: [project, global]).port # => 5000
  #
  # @see Disposita.define_schema
  # @see Disposita::Configuration
  class Schema
    # @return [Symbol] logical name of the configuration domain.
    attr_reader :name

    # @return [Integer] consumer-owned persisted schema version.
    attr_reader :version

    # @api private
    # @return [Array<Disposita::Internal::SettingDefinition>] declared settings.
    attr_reader :settings
    private :settings

    # Builds a schema from already validated definitions.
    # @api private
    #
    # Consumers normally create schemas with {Disposita.define_schema}; this
    # initializer is public primarily to keep Schema as a normal Ruby object.
    #
    # @param name [String, Symbol] logical domain name.
    # @param version [Integer, #to_int] persisted schema version.
    # @param settings [Array<Disposita::Internal::SettingDefinition>] settings
    #   created by the schema DSL.
    # @return [Disposita::Schema]
    # @raise [ArgumentError, TypeError] if +version+ cannot be converted to an
    #   Integer.
    def initialize(name:, version:, settings:)
      @name = name.to_sym
      @version = Integer(version)
      @settings = settings.freeze
      @settings_by_path = settings.to_h { |setting| [setting.path, setting] }.freeze
      freeze
    end

    # Enumerates immutable public metadata in declaration order.
    #
    # Custom Sources can use :path (dotted String) and :env without accessing
    # internal definitions. All fields match {#describe}; secrets are redacted.
    # @yieldparam metadata [Hash] deeply frozen metadata for one setting.
    # @return [Enumerator<Hash>, Disposita::Schema] an Enumerator without a
    #   block, otherwise this schema.
    def each_setting
      return enum_for(__method__) unless block_given?

      settings.each { |item| yield describe(item.path) }
      self
    end

    # Returns user-oriented metadata for one declared setting.
    #
    # The returned Hash is suitable for CLI help, documentation generators and
    # configuration editors. Secret values are never included; only metadata
    # such as whether a setting is secret is exposed. Secret defaults are
    # replaced by +[REDACTED]+; absent defaults remain +nil+.
    #
    # @param path [String, Array<String, Symbol>, Symbol] setting path.
    # @return [Hash, nil] frozen metadata Hash, or +nil+ for an unknown path.
    # @example
    #   schema = Disposita.define_schema(:app) do
    #     setting :port, type: Integer, default: 3000
    #   end
    #   schema.describe(:port)[:default] # => 3000
    def describe(path)
      item = @settings_by_path[normalize_path(path)]
      return unless item

      metadata = {
        path: item.key,
        type: Internal::TypeAdapter.describe(item.type),
        default: if item.default?
                   item.secret? ? "[REDACTED]" : item.default
                 end,
        has_default: item.default?,
        required: item.required?,
        secret: item.secret?,
        env: item.env,
        description: item.description
      }
      Internal::HashTools.deep_freeze(Internal::HashTools.deep_dup(metadata))
    end

    # Resolves explicit sources listed from highest to lowest precedence.
    #
    # For each setting, the first source providing a value wins. Nested hashes
    # merge recursively; arrays and scalars are selected whole. Defaults are
    # always the final fallback. No sources means no ENV or file reads.
    # A setting declared +required: true+ must have a value in the final
    # Configuration; the consumer need not supply it explicitly. A declared
    # default satisfies that requirement, so +required: true, default: 30+ is
    # valid. Combining +required: true+ with +optional: true+ is invalid.
    # Coercion and validation run after merging. Every supplied source is checked
    # for unknown settings and unsupported schema versions, even when shadowed.
    # @param sources [Array<Disposita::Source>] sources from highest to lowest precedence.
    # @return [Disposita::Configuration] immutable typed values with provenance.
    # @raise [Disposita::MissingSettingError] when a required value is absent.
    # @raise [Disposita::CoercionError] when the selected value cannot be coerced.
    # @raise [Disposita::ValidationError] when validation fails.
    # @raise [Disposita::UnknownSettingError] when a source has undeclared keys.
    # @raise [Disposita::VersionError] when persisted versions are invalid or newer.
    def resolve(sources: [])
      data = {}
      provenance = {}

      sources.each do |source|
        raw = source.read(self)
        validate_version!(raw)
        normalized = normalize_layer(raw)
        reject_unknown!(normalized)
        data = Internal::DeepMerge.call(data, normalized)
        mark_provenance!(provenance, normalized, source.name)
      end

      data = Internal::DeepMerge.call(data, defaults)
      provenance = default_provenance.merge(provenance)
      resolved = coerce_and_validate(data)
      Configuration.new(schema: self, data: resolved, provenance: provenance)
    end

    # Validates and writes explicit partial data to one writable source.
    #
    # Writes deliberately do not serialize a fully resolved Configuration: ENV,
    # runtime overrides and defaults could otherwise leak into an unrelated
    # file. Callers must choose both the target source and the values to persist.
    # The current schema version is added automatically.
    #
    # @param source [Disposita::Source] explicit writable target.
    # @param data [Hash] partial configuration values to persist.
    # @return [Object] whatever the source returns from +#write+; file sources
    #   return their path.
    # @raise [Disposita::SaveError] if the source is read-only or persistence
    #   fails.
    # @raise [Disposita::ValidationError] if supplied values are invalid.
    # @raise [Disposita::UnsafeSecretPersistenceError] if the target source
    #   refuses secret values.
    # @example
    #   schema = Disposita.define_schema(:app) do
    #     namespace(:server) { setting :port, type: Integer }
    #   end
    #   file = Disposita::Sources::File.new(".app.yml", name: :project)
    #   schema.write(file, server: { port: 9292 })
    def write(source, data)
      raise SaveError, "source #{source.name.inspect} is read-only" unless source.writable?

      normalized = Internal::HashTools.symbolize(data)
      reject_unknown!(normalized)
      validated = validate_partial(normalized)
      payload = { version: version }
      payload = Internal::DeepMerge.call(payload, validated)
      source.write(self, payload)
    end

    private

    def normalize_path(path)
      case path
      when String then path.split(".").map!(&:to_sym)
      when Array then path.map(&:to_sym)
      else Array(path).map!(&:to_sym)
      end
    end

    def defaults
      settings.each_with_object({}) do |setting, result|
        next unless setting.default?

        Internal::HashTools.set(result, setting.path, Internal::HashTools.deep_dup(setting.default))
      end
    end

    def default_provenance
      settings.each_with_object({}) do |setting, result|
        result[setting.path] = :default if setting.default?
      end
    end

    def normalize_layer(raw)
      raw = Internal::HashTools.symbolize(raw)
      raw.except(:version)
    end

    def validate_version!(raw)
      raw = Internal::HashTools.symbolize(raw)
      persisted = raw[:version]
      return unless persisted

      persisted = Integer(persisted)
      return if persisted <= version

      raise VersionError, "configuration version #{persisted} is newer than schema version #{version}"
    rescue ArgumentError, TypeError
      raise VersionError, "configuration version must be an integer"
    end

    def reject_unknown!(data, prefix = [])
      data.each do |key, value|
        path = prefix + [key]
        if value.is_a?(Hash) && settings.any? { |item| item.path[0, path.size] == path }
          reject_unknown!(value, path)
        elsif !@settings_by_path.key?(path)
          raise UnknownSettingError, "unknown setting: #{path.join('.')}"
        end
      end
    end

    def mark_provenance!(provenance, layer, source_name)
      Internal::HashTools.flatten_keys(layer).each { |path| provenance[path] ||= source_name }
    end

    def coerce_and_validate(data)
      settings.each_with_object({}) do |setting, result|
        value = Internal::HashTools.get(data, setting.path)
        if value.equal?(Internal::UNDEFINED)
          raise MissingSettingError, "missing required setting: #{setting.key}" if setting.required?

          next
        end

        Internal::HashTools.set(result, setting.path, validate_value(setting, value))
      end
    end

    def validate_partial(data)
      settings.each_with_object({}) do |setting, result|
        value = Internal::HashTools.get(data, setting.path)
        next if value.equal?(Internal::UNDEFINED)

        Internal::HashTools.set(result, setting.path, validate_value(setting, value))
      end
    end

    def coerce_value(setting, value)
      return value if Internal::TypeAdapter.valid?(setting.type, value)
      return Internal::TypeAdapter.coerce(setting.type, value) if setting.coerce?

      expected = Internal::TypeAdapter.describe(setting.type)
      raise ValidationError, "#{setting.key} expected #{expected}, got #{value.class}"
    end

    def validate_value(setting, value)
      resolved = coerce_value(setting, value)

      if setting.validator && !setting.validator.call(resolved)
        raise ValidationError, "validation failed for #{setting.key}"
      end

      Internal::HashTools.deep_dup(resolved)
    rescue CoercionError => e
      detail = setting.secret? ? "[REDACTED] cannot coerce secret value" : e.message
      raise CoercionError, "#{setting.key}: #{detail}", cause: setting.secret? ? nil : e
    end
  end
end
