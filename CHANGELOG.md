# Changelog

All notable changes to Disposita will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows Semantic Versioning.

## [Unreleased]

### Fixed

- Load YARD correctly and keep Markdown out of Ruby source parsing; validate documentation in CI.
- Redact secret defaults in schema metadata and preserve caller-owned path arrays.

### Added

- Complete namespace/helper documentation and regression coverage for source contracts, safe YAML and failed atomic writes.

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
