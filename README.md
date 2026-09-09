# Disposita

Declarative, typed configuration for Ruby applications and gems. Define the settings your application owns, choose explicit sources, and resolve an immutable configuration.

## Define a schema

```ruby
require "disposita"

AppSchema = Disposita.define_schema(:app, version: 1) do
  namespace :server do
    setting :host, type: String, default: "localhost"
    setting :port, type: Integer, default: 3000
  end
end
```

`Disposita.define_schema` returns a `Disposita::Schema`. Requiring the gem and defining a schema do not read configuration files or ENV, create directories, or register global configuration state.

## Resolve defaults

```ruby
config = AppSchema.resolve

config.server.host # => "localhost"
config.server.port # => 3000
```

No external source participates unless supplied explicitly. Declaring a setting's `env:` name does not enable ENV reads by itself.

## Resolve multiple sources

Building on `AppSchema` above:

```ruby
config = AppSchema.resolve(
  sources: [
    Disposita::Sources::Environment.new(prefix: "APP", name: :environment),
    Disposita::Sources::File.new(".app.yml", name: :project)
  ]
)
```

Sources are ordered from highest to lowest precedence. For each setting, Disposita uses the first source that provides a value, falling back through the remaining sources and finally to the schema default.

For example, with `APP_SERVER_PORT=5000` and this `.app.yml`:

```yaml
server:
  host: example.com
  port: 4000
```

The result is `config.server.port == 5000` and `config.server.host == "example.com"`. ENV supplies the port, the project supplies the host, and defaults fill any remaining settings.

Namespaces merge recursively. Scalars and arrays are selected whole from the first source providing them; arrays are never concatenated. An explicit `false`, `nil`, or empty array is a supplied value, not absence, and must satisfy the schema's type. An invalid winning value raises an error instead of falling back to another source. Every source is checked for unknown settings and unsupported schema versions, even if its values are shadowed.

## Installation

Disposita 0.2.0 requires Ruby 3.2 or newer. After the release is published, use:

```ruby
gem "disposita", "~> 0.2.0"
```

Then run `bundle install`. Breaking changes from the previous release are recorded in [CHANGELOG.md](CHANGELOG.md).

## Public model

```text
define_schema → Schema → Sources → resolve → Configuration
```

- `Disposita.define_schema` describes which settings exist.
- `Source#read(schema)` obtains partial raw data.
- `Schema#resolve(sources: [])` applies precedence, recursive merge, defaults, coercion and validation, and records provenance.
- `Configuration` is the final immutable result.
- `Schema#write(source, data)` persists explicitly to one selected source.

## Namespaces, types and validation

```ruby
ServiceSchema = Disposita.define_schema(:service) do
  namespace :git do
    setting :transport, type: Disposita::Types.enum(:ssh, :https), default: :ssh
    setting :mirrors, type: Disposita::Types.array(String), default: []
  end
  setting :enabled, type: Disposita::Types.boolean, default: true
  setting :ratio, type: Float, default: 1.25
  setting :mode, type: Symbol, default: :development
  setting :timeout, type: Integer, required: true, default: 30 do |value|
    value.positive?
  end
end
```

Namespaces can nest. Each setting or namespace name must be a non-empty String or Symbol without `.`; dots separate path segments, so use a namespace to declare `server.port`. No additional naming convention is imposed. Use Ruby `String`, `Integer`, `Float`, and `Symbol`, plus `Types.boolean`, `Types.enum(...)` and `Types.array(member_type)`. Use these factories instead of instantiating their implementation classes. Disposita remains a small configuration library with no Typio or Rails dependency.

Coercion follows the declared type: `"5432"` becomes integer `5432`, `"1.25"` becomes float `1.25`, `"true"`/`"false"` become booleans, and `"ssh"` becomes `:ssh` for Symbol or an appropriate enum. Strings remain strings when `type: String` is declared. Array members use their declared member type; ENV strings are not implicitly split into arrays. Sources return raw data and do not infer types.

| Setting option | Default | Meaning |
| --- | --- | --- |
| `type:` | Required | Ruby class or configuration type. Custom type objects may implement `valid?` and optionally `coerce`; otherwise validation uses `===`. |
| `default:` | Absent | Final fallback, coerced and validated like source data. Explicit `nil` counts as present and must satisfy the type. |
| `required:` | `false` | A value must exist after all sources and defaults resolve. May be satisfied by a default. |
| `optional:` | `false` | Documents that absence is allowed. Cannot be true together with `required: true`. |
| `env:` | `nil` | Explicit environment variable name, used only by an Environment source. |
| `secret:` | `false` | Redact diagnostics and apply persistence policy. |
| `description:` | `nil` | Text included in public metadata. |
| `coerce:` | `true` | Set false to require already typed values. |

Defaults are copied and deeply frozen when the setting is declared. Mutating the original arrays, hashes or strings afterward does not change the schema. Metadata returned by `describe` is also deeply frozen and cannot modify the stored default.

`required: true` means the setting must have a value in the final Configuration; it does not require the consumer to supply it explicitly. For example, `required: true, default: 30` resolves to `30` without an external source. Combining `required: true` with `optional: true` remains invalid.

Settings without `required: true` may be absent. Missing values are omitted from `to_h`. A validator block runs after coercion and must return a truthy value. Required absence raises `MissingSettingError`; coercion and custom validation failures raise `CoercionError` and `ValidationError`. Unknown keys raise `UnknownSettingError`, including unknown empty mappings. Typos are never silently ignored.

## Environment source

```ruby
AuthSchema = Disposita.define_schema(:auth) do
  setting :token, type: String, secret: true, env: "MY_SPECIAL_TOKEN"
  setting :timeout, type: Integer, default: 30
end

environment = Disposita::Sources::Environment.new(
  env: { "MY_SPECIAL_TOKEN" => "example-token", "APP_TIMEOUT" => "10" },
  prefix: "APP",
  name: :environment
)
config = AuthSchema.resolve(sources: [environment])
```

`env:` on the source defaults to `ENV` because creating that source is an explicit choice. `prefix:` derives uppercase names from the full dotted path: `server.port` becomes `APP_SERVER_PORT`. A setting's explicit name replaces the derived name; if the explicit variable is absent, the derived name is not used. Without a prefix, only explicitly named variables are read. Unrelated environment variables are ignored.

## Memory source and runtime values

```ruby
runtime = Disposita::Sources::Memory.new({ server: { port: 9292 } }, name: :runtime)
environment = Disposita::Sources::Environment.new(prefix: "APP")
project = Disposita::Sources::File.new(".app.yml", name: :project)
global = Disposita::Sources::File.new(
  File.join(Disposita::Paths.user_config("app"), "config.yml"), name: :global
)
config = AppSchema.resolve(sources: [runtime, environment, project, global])
```

The priority here is runtime, environment, project, global, then defaults. Memory is a read-only source for tests, embedding and programmatic values, with default name `:memory`. It normalizes mapping keys without coercing values. There is no special runtime argument on Schema.

## Configuration, provenance and explain

```ruby
config = AppSchema.resolve(sources: [
  Disposita::Sources::Memory.new({ server: { port: "5000" } }, name: :runtime)
])
config.server.port # => 5000
config[:server][:host] # => "localhost"
config.source_of("server.port") # => :runtime
config.source_of([:server, :host]) # => :default
config.explain("server.port")
# => { path: "server.port", value: 5000, source: :runtime }
copy = config.to_h
```

Resolved values are recursively frozen; `to_h` returns a detached mutable copy. Resolution does not freeze caller-owned source values. `source_of` returns nil when no value was supplied. `explain` reports the selected value and source, not the full candidate chain. For an absent optional setting it reports nil value/source; for an unknown setting it raises `KeyError`. `inspect` and `explain` redact secrets; ordinary access and `to_h` return actual values.

## File source and safe YAML

Missing files are empty sources. Files use a codec with `load(String)` and `dump(Hash)` methods, supplied through `format:`; the bundled codec is `Disposita::Formats::YAML`.

YAML loading uses Psych safe APIs with Ruby objects, arbitrary classes, Symbol tags and aliases disabled. Runtime Symbols are dumped as plain strings and recovered through schema coercion. No JSON or TOML codecs are included.

YAML interprets some unquoted values as special types before schema coercion. For example, `release_date: 2026-09-09` is interpreted as a Date and rejected by the safe loader, even if the setting declares `type: String`. Quote such values to keep them as strings:

```yaml
release_date: "2026-09-09"
```

Date is not a permitted class in Disposita 0.2.0.

## Explicit persistence

Reading may combine many sources. Writing always targets exactly one source.

```ruby
project = Disposita::Sources::File.new(".app.yml", name: :project)
AppSchema.write(project, server: { port: 9292 })
```

`write` validates only the explicitly supplied partial values and adds the schema version. It replaces the target's contents with that payload. It never automatically persists ENV, runtime, defaults, other sources or a resolved configuration; there is no `config.save!`.

File writes create a temporary file in the destination directory, write, flush, fsync and rename it into place. Temporary files are cleaned up on failure. Files have restrictive permissions (`0600` on supported platforms). Failed replacement leaves the existing file intact. Parent directories are created only during explicit writes.

## Secrets

`secret: true != encryption`. It means diagnostic redaction, protection against accidental disclosure and an explicit persistence policy. Disposita is not a secret manager.

Every source may read secret values. `Source#allows_secret_persistence?` describes permission to **write** them, and defaults to false. File rejects secret writes unless explicitly opted in:

```ruby
private_store = Disposita::Sources::File.new(
  "~/.config/app/private.yml", name: :private, allow_secrets: true
)
AuthSchema.write(private_store, token: "example-token")
```

Secret defaults are redacted in metadata; secret values are redacted in `inspect`, `explain` and coercion errors. Direct access and exports contain real secrets, so they are not logging APIs.

## Paths

`Paths.user_config("app")` follows Linux/XDG (`$XDG_CONFIG_HOME` or `~/.config`), macOS Application Support, and Windows APPDATA with LOCALAPPDATA fallback. The application name must be a single directory name without traversal or path separators. Optional `env:` and `host_os:` arguments allow deterministic path selection.

`Paths.project(root, relative)` resolves a consumer-selected project path and rejects traversal outside the root. These helpers compute paths without creating directories. The consumer chooses the layout; no `.disposita` or other project directory is imposed.

## Introspection and custom Sources

`Schema#describe(path)` returns a deeply frozen metadata hash, or nil for an unknown path. `Schema#each_setting` yields the same hashes in declaration order and returns an Enumerator without a block.

```ruby
AppSchema.describe("server.port")
# => { path: "server.port", type: "Integer", default: 3000,
#      has_default: true, required: false, secret: false, env: nil, description: nil }
AppSchema.each_setting.map { |metadata| metadata[:path] }
# => ["server.host", "server.port"]
```

Secret defaults appear as `[REDACTED]`. Metadata never exposes internal definition or type adapter objects.

A custom Source can work entirely through public metadata:

```ruby
class DatabaseSource < Disposita::Source
  def initialize(rows, name: :database)
    super(name: name)
    @rows = rows # An application-owned mapping of dotted paths to raw values.
  end

  def read(schema)
    schema.each_setting.each_with_object({}) do |metadata, data|
      path = metadata.fetch(:path)
      next unless @rows.key?(path)

      segments = path.split(".").map(&:to_sym)
      parent = segments[0...-1].reduce(data) { |node, key| node[key] ||= {} }
      parent[segments.last] = @rows.fetch(path)
    end
  end
end

config = AppSchema.resolve(sources: [DatabaseSource.new({ "server.port" => "6000" })])
config.server.port # => 6000
```

Custom Sources implement `read(schema)` and inherit `name`, read-only `writable?`, and denied `allows_secret_persistence?`. Writable adapters implement `writable?`, `write(schema, data)` and enforce their persistence policy. Schema handles validation; sources own storage mechanics.

## Schema versions

`Disposita.define_schema(:app, version: 1)` uses a consumer-owned version independent of `Disposita::VERSION` (`0.2.0`). Explicit writes include `version:`. Resolution rejects persisted versions newer than the schema and malformed version values. Complex migrations are not included.

## Development and API documentation

```sh
bundle install
COVERAGE=true bundle exec rspec
bundle exec rubocop
bundle exec rake yard
bundle exec rake build
```

`bundle exec rake` runs RuboCop, specs and YARD. Coverage thresholds remain line >=95% and branch >=90%. CI tests Ruby 3.2, 3.3, 3.4 and 4.0. YARD uses README as the homepage, writes documentation to `doc/`, and treats warnings as failures.

Public contracts are `Disposita.define_schema`, Schema, Configuration, Source and its three built-in implementations, the Types factories, Paths and the YAML codec. `Internal::*`, namespace implementation nodes, constructors for resolved objects, and dot-access machinery are implementation details excluded from public documentation.

## License

MIT.
