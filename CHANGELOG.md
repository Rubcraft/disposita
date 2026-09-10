# Changelog

All notable changes to Disposita will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows Semantic Versioning.

## [0.2.1] - 2026-09-09

### Fixed

- Include `.yardopts` and the custom YARD template in the gem so documentation generated from the package preserves public API filtering.
- Centralize SimpleCov configuration in `.simplecov`, preserving line >=95% and branch >=90% thresholds.
- Add the public-gem metadata `homepage_uri` and `allowed_push_host` required by Rubcraft.
- Run dependency audit and gem build in CI, and verify documentation generated from the unpacked gem in CI and release verification.

## [0.2.0] - 2026-09-09

### Breaking

- Setting and namespace names must be non-empty String or Symbol path segments without dots.

- Renamed `Disposita.define` to `Disposita.define_schema`, without compatibility aliases.
- Removed `Schema#load`; `Schema#resolve(sources: [])` is the only resolution API and accepts no positional arguments.
- Sources are now listed from highest to lowest precedence: the first source wins, recursively within namespaces; arrays are selected whole. Defaults remain the final fallback.
- Removed special `env`, `env_prefix`, and runtime `overrides` handling from Schema. Environment and runtime values are explicit Sources.
- Renamed `Sources::Hash` to `Sources::Memory`, including its require path, without an alias.
- Removed public `Schema#settings` and `Schema#setting`. Use `describe` and `each_setting` metadata instead.
- Renamed `Source#allows_secrets?` to `allows_secret_persistence?` to distinguish writing policy from reading secrets. File's explicit `allow_secrets:` opt-in remains.
- Made YAML serialization and platform detection helpers private; excluded internal classes, constructors and dot-access mechanisms from public YARD documentation.

### Added

- Complete namespace/helper documentation and regression coverage for source contracts, safe YAML and failed atomic writes.

- Public `Schema#each_setting` introspection for custom Sources, with deeply frozen metadata and redacted secret defaults.
- Regression coverage for first-source-wins nested merges, source fallback, provenance, API boundaries and explicit ENV resolution.

### Changed

- Rewrote README and YARD examples for the explicit source-based 0.2.0 API.
- Provenance and `explain` now report the first source that supplies a value. `explain` keeps its selected-value format.
- A default may satisfy `required: true`; `required: true, optional: true` remains invalid.
- Resolution copies selected values before freezing, preserving caller-owned source data.

### Fixed

- Copy and deeply freeze schema defaults at declaration time so later mutation of caller-owned containers or strings cannot change the schema.

- Reject traversal in user configuration application names and handle filesystem-root project paths.
- Reject unknown empty mappings instead of silently ignoring them.
- Redact secret values from coercion errors.
- Load YARD correctly and keep Markdown out of Ruby source parsing; validate documentation in CI.
- Redact secret defaults in schema metadata and preserve caller-owned path arrays.

## [0.1.0] - 2026-09-04

### Added

- Consumer-owned schema DSL with nested namespaces.
- Typed settings with conservative coercion and custom validation.
- Defaults, required/optional settings and strict unknown-setting detection.
- Boolean, enum and typed-array helpers for configuration-oriented types.
- Immutable resolved configuration with dot access and detached hash export.
- Explicit layered resolution and source provenance.
- Environment source with explicit names or generated prefixes.
- In-memory source for runtime overrides and tests.
- Safe YAML loading and serialization.
- Atomic YAML file persistence with explicit writable targets.
- Secret metadata, diagnostic redaction and opt-in secret file persistence.
- Cross-platform user configuration path helpers.
- Schema introspection and schema version checks.
- Structured Disposita error hierarchy.
