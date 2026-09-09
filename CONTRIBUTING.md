# Contributing

Contributions are welcome through pull requests.

Before submitting a change:

```bash
bundle install
COVERAGE=true bundle exec rspec
bundle exec rubocop
bundle exec rake yard
```

Keep public APIs small and consumer-owned. New behavior should include focused specs organized under the matching subsystem. Internal implementation details belong under `Disposita::Internal` unless they are intentionally part of the extension contract.
