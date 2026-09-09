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
  # ordered: later sources override earlier sources, while schema defaults form
  # the lowest-precedence layer. Environment and runtime overrides may be added
  # conveniently through {#load}.
  #
  # @example Resolve ordered layers
  #   schema = Disposita.define(:app) do
  #     setting :port, type: Integer, default: 3000
  #   end
  #
  #   global  = Disposita::Sources::Hash.new({ port: 4000 }, name: :global)
  #   project = Disposita::Sources::Hash.new({ port: 5000 }, name: :project)
  #
  #   schema.resolve([global, project]).port # => 5000
  #
  # @see Disposita.define
  # @see Disposita::Configuration
  class Schema
    # @return [Symbol] logical name of the configuration domain.
    attr_reader :name

    # @return [Integer] consumer-owned persisted schema version.
    attr_reader :version

    # @return [Array<Disposita::Internal::SettingDefinition>] declared settings.
    attr_reader :settings

    # Builds a schema from already validated definitions.
    #
    # Consumers normally create schemas with {Disposita.define}; this
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

    # Finds a setting definition by dotted, array or scalar path.
    #
    # This is the lowest-level introspection method. Most user-facing tooling
    # should prefer {#describe}, which returns a stable metadata Hash instead of
    # exposing the internal definition object.
    #
    # @param path [String, Array<String, Symbol>, Symbol] setting path,
    #   for example +"git.transport"+ or +[:git, :transport]+.
    # @return [Disposita::Internal::SettingDefinition, nil] definition when the
    #   path exists, otherwise +nil+.
    def setting(path)
      @settings_by_path[normalize_path(path)]
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
    #   schema.describe("git.transport")
    #   # => {
    #   #      path: "git.transport",
    #   #      type: "enum(:ssh, :https)",
    #   #      default: :ssh,
    #   #      has_default: true,
    #   #      required: false,
    #   #      secret: false,
    #   #      env: nil,
    #   #      description: "Preferred Git transport"
    #   #    }
    def describe(path)
      item = setting(path)
      return unless item

      {
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
      }.freeze
    end

    # Resolves configuration using convenient optional ENV and runtime layers.
    #
    # Sources supplied in +sources+ are applied in order. If +env+ is provided,
    # an Environment source is appended after them. If +overrides+ is provided,
    # an in-memory runtime source is appended last, giving runtime values the
    # highest precedence.
    #
    # No global ENV lookup happens unless +env+ is explicitly provided. Passing
    # +ENV+ is therefore an application decision rather than a side effect of
    # loading Disposita.
    #
    # @param sources [Array<Disposita::Source>] ordered low-to-high precedence
    #   configuration sources.
    # @param env [Hash, nil] environment-like Hash. When present, declared +env+
    #   names or +env_prefix+ derived names are read from it.
    # @param env_prefix [String, nil] prefix used to derive names such as
    #   +APP_SERVER_PORT+ from the setting path +server.port+.
    # @param overrides [Hash, nil] highest-precedence runtime values. These are
    #   never persisted automatically.
    # @return [Disposita::Configuration] immutable typed configuration.
    # @raise [Disposita::ValidationError] if a value cannot be validated.
    # @raise [Disposita::UnknownSettingError] if a source contains undeclared
    #   settings.
    # @raise [Disposita::VersionError] if persisted data declares a newer schema
    #   version than this runtime understands.
    # @example
    #   config = schema.load(
    #     sources: [project_source],
    #     env: ENV,
    #     env_prefix: "MY_APP",
    #     overrides: { server: { port: 9292 } }
    #   )
    def load(sources: [], env: nil, env_prefix: nil, overrides: nil)
      effective_sources = Array(sources).dup
      effective_sources << Sources::Environment.new(env: env, prefix: env_prefix) if env
      effective_sources << Sources::Hash.new(overrides, name: :runtime) if overrides
      resolve(effective_sources)
    end

    # Resolves an explicit ordered list of sources.
    #
    # Defaults are applied first. Each source then contributes a partial layer;
    # hashes are deep-merged, while arrays and scalar values replace lower
    # precedence values. The final representation is coerced and validated only
    # after all layers have been combined.
    #
    # @param sources [Array<Disposita::Source>, Disposita::Source] source or
    #   ordered sources from lowest to highest precedence.
    # @return [Disposita::Configuration] immutable resolved configuration with
    #   provenance information for each selected value.
    # @raise [Disposita::MissingSettingError] when a required setting remains
    #   absent after all layers are resolved.
    # @raise [Disposita::CoercionError] when a value cannot be coerced to its
    #   declared type.
    # @raise [Disposita::UnknownSettingError] when input contains an undeclared
    #   setting.
    # @raise [Disposita::VersionError] when a source is newer than the schema.
    def resolve(sources)
      data = defaults
      provenance = default_provenance

      Array(sources).each do |source|
        raw = source.read(self)
        validate_version!(raw)
        normalized = normalize_layer(raw)
        reject_unknown!(normalized)
        data = Internal::DeepMerge.call(data, normalized)
        mark_provenance!(provenance, normalized, source.name)
      end

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

    def reject_unknown!(data)
      known = settings.map(&:path)
      Internal::HashTools.flatten_keys(data).each do |path|
        next if known.include?(path)

        raise UnknownSettingError, "unknown setting: #{path.join('.')}"
      end
    end

    def mark_provenance!(provenance, layer, source_name)
      Internal::HashTools.flatten_keys(layer).each { |path| provenance[path] = source_name }
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

      resolved
    rescue CoercionError => e
      raise CoercionError, "#{setting.key}: #{e.message}"
    end
  end
end
