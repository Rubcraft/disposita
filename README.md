# Disposita

Declarative, typed and layered configuration infrastructure for Ruby applications, gems and CLIs.

Disposita provides the mechanics of configuration while leaving ownership and meaning with the consumer. It does not know what `:ssh`, `production` or a timeout mean to your application; it only knows how those values are declared, loaded, coerced, validated, layered and persisted.

## Why Disposita?

Configuration tends to grow into repeated infrastructure: parsers, defaults, environment variables, per-user paths, project overrides, validation, persistence and diagnostics. Disposita centralizes that infrastructure without making a toolkit or framework the owner of every consumer's configuration.

## Installation

Add to your Gemfile:

```ruby
gem "disposita"
```

Then run `bundle install`.

## Define a schema

```ruby
require "disposita"

SCMConfig = Disposita.define(:scm, version: 1) do
  namespace :git do
    setting :default_remote,
      type: String,
      default: "origin",
      description: "Default Git remote"

    setting :transport,
      type: Disposita::Types.enum(:ssh, :https),
      default: :ssh,
      env: "SCM_GIT_TRANSPORT"

    setting :timeout,
      type: Integer,
      default: 30

    setting :token,
      type: String,
      secret: true,
      optional: true
  end
end
```

`Disposita.define` returns a schema object. It does not register global mutable state and it performs no filesystem or environment reads by itself.

### Setting options

Within `Disposita.define`, `namespace(name) { ... }` groups settings; namespaces can nest.
`setting(name, type:, ...) { |value| ... }` declares a leaf. Its optional validator runs after coercion and must return a truthy value.

| Option | Default | Meaning |
| --- | --- | --- |
| `type:` | Required | Ruby class, a built-in type helper, or an object implementing `valid?` and optionally `coerce`. Otherwise validation uses `===`. |
| `default:` | Absent | Value used when no source provides one. An explicit `nil` still counts as a default and must satisfy the declared type. |
| `required:` | `false` | Reject resolution if the setting is absent. Cannot be combined with a default or `optional: true`. |
| `optional:` | `false` | Explicitly documents that absence is allowed; settings are already optional unless required. |
| `env:` | `nil` | Explicit variable name, taking precedence over generated names. |
| `secret:` | `false` | Redact diagnostics and deny ordinary file persistence. |
| `description:` | `nil` | Consumer-facing text returned by schema introspection. |
| `coerce:` | `true` | Convert raw input before checking semantic validation. Set false for strict values. |

`Schema#load` accepts no arguments for defaults-only resolution. `Schema#resolve` requires an explicit source or array; use `resolve([])` for defaults alone.

## Resolve layers

```ruby
global = Disposita::Sources::File.new(
  File.join(Disposita::Paths.user_config("scm"), "config.yml"),
  name: :global
)

project = Disposita::Sources::File.new(
  ".scm.yml",
  name: :project
)

config = SCMConfig.load(
  sources: [global, project],
  env: ENV,
  env_prefix: "SCM",
  overrides: { git: { timeout: 10 } }
)
```

Precedence is explicit and follows source order. Schema defaults are always the lowest layer; runtime overrides supplied to `load` are the highest layer.

```text
defaults < global < project < environment < runtime
```

## Typed access

```ruby
config.git.default_remote # => "origin"
config.git.transport      # => :ssh
config.git.timeout        # => 10
```

Resolved configuration is immutable. `to_h` returns a detached copy for interoperability.

## Coercion

Disposita performs conservative coercion when a setting allows it (the default):

```text
"5432"  -> Integer
"1.5"   -> Float
"ssh"   -> Symbol / enum value
"false" -> Boolean
```

Use `coerce: false` to require an already-typed value.

```ruby
setting :strict_port, type: Integer, coerce: false
```

## Validation

A setting can add consumer-owned semantic validation:

```ruby
setting :timeout, type: Integer, default: 30 do |value|
  value.positive?
end
```

Disposita runs the rule; the consumer defines what the rule means.

## Environment variables

A setting may name its environment variable explicitly:

```ruby
setting :transport, type: Symbol, env: "SCM_GIT_TRANSPORT"
```

Or a source may generate names from a prefix and setting path:

```ruby
Disposita::Sources::Environment.new(prefix: "SCM")
# git.transport -> SCM_GIT_TRANSPORT
```

## Safe YAML

The bundled file source uses `Psych.safe_load` and disables Ruby-object deserialization and YAML aliases. Symbols are serialized as strings and coerced back according to the schema.

```yaml
version: 1
git:
  transport: ssh
```

Disposita intentionally ships YAML only in 0.1.0. The format boundary is isolated so JSON or TOML can be added without changing schema ownership or resolution semantics.

## Explicit writes

Reading may combine many layers. Writing always targets one explicit writable source.

```ruby
project = Disposita::Sources::File.new(".scm.yml", name: :project)

SCMConfig.write(project, git: { transport: :https })
```

Writes are validated and performed atomically through a temporary file followed by rename.

Defaults are not written automatically: consumers persist only the overrides they choose.

## Secrets

A setting can be marked as sensitive:

```ruby
setting :token, type: String, secret: true
```

The actual value remains available to application code:

```ruby
config.git.token
```

But diagnostics redact it:

```ruby
config.inspect
# => #<Disposita::Configuration git=#<... token=[REDACTED]>>
```

Normal file sources reject secret persistence by default. A consumer must opt in explicitly:

```ruby
private_store = Disposita::Sources::File.new(
  "~/.config/scm/private.yml",
  name: :private,
  allow_secrets: true
)
```

Secret-aware behavior is not encryption. Disposita 0.1.0 deliberately does not implement cryptographic storage, key management, Vault, KMS or OS keychains.

## Provenance

Disposita tracks which layer supplied the winning value:

```ruby
config.source_of("git.transport")
# => :project

config.explain("git.transport")
# => { path: "git.transport", value: :https, source: :project }
```

Secret values are redacted from `explain`.

## Paths

User-level configuration paths follow platform conventions:

- Linux: `$XDG_CONFIG_HOME/<app>` or `~/.config/<app>`
- macOS: `~/Library/Application Support/<app>`
- Windows: `%APPDATA%\<app>` (falling back to `%LOCALAPPDATA%`)

Project paths remain consumer-owned:

```ruby
Disposita::Paths.project(Dir.pwd, ".rubcraft/scm.yml")
```

Disposita never imposes `.rubcraft`, `.disposita`, or another project directory.

## Schema introspection

```ruby
SCMConfig.describe("git.transport")
# => {
#   path: "git.transport",
#   type: "enum(:ssh, :https)",
#   default: :ssh,
#   has_default: true,
#   required: false,
#   secret: false,
#   env: "SCM_GIT_TRANSPORT",
#   description: nil
# }
```

This metadata is intended to support future CLI help, documentation and UI tooling without coupling Disposita to a particular CLI framework. Secret defaults appear as `[REDACTED]`, while `has_default` still indicates whether a default exists. Direct configuration access and `to_h` return actual values.

Prefer `describe` for diagnostic tooling. The lower-level `setting` and `settings` methods expose internal definition objects, including actual defaults; they are not safe logging representations.

## Schema versions

Each schema has a version and file sources may persist it. Disposita rejects configuration produced by a newer schema version. Automatic migrations are intentionally deferred beyond 0.1.0 so the migration contract can be designed without freezing a premature API.

## Ownership model

Disposita owns:

- schema infrastructure
- type checking and configuration-oriented coercion
- loading and persistence primitives
- layering and provenance
- conventional user paths
- validation mechanics
- secret-aware diagnostics

Consumers own:

- the schema itself
- project file locations
- layer policy and precedence
- what each setting means
- semantic validation rules
- whether and where secrets may be persisted

A library such as SCM can remain configuration-agnostic while `SCM CLI`, Rubcraft Toolkit, or another application defines its own Disposita schema around SCM.

## Non-goals for 0.1.0

Disposita does not aim to be a general-purpose type system, secret manager, encryption framework, Rails settings singleton, command-line parser or business-rule engine.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake
COVERAGE=true bundle exec rspec
bundle exec rake yard
```

The test suite is organized by public behavior and subsystem, with integration-style schema specs separated from source/format/path specs.

## License

MIT.

## API documentation

Disposita's public API is documented with YARD comments that explain not only
method signatures, but also ownership, precedence, persistence safety and common
usage patterns. Generate the local documentation with:

```sh
bundle exec rake yard
```

The generated site is written to `doc/`. CI generates it with warnings treated as failures. Internal implementation objects are
marked with `@api private`; applications should build against the documented
public objects such as `Disposita`, `Disposita::Schema`,
`Disposita::Configuration`, `Disposita::Source`, `Disposita::Sources::*`,
`Disposita::Types` and `Disposita::Paths`.
