# Security Policy

Disposita treats configuration as potentially sensitive input.

Please report suspected vulnerabilities privately to the Rubcraft maintainers rather than opening a public issue with exploit details or secrets.

## Security boundaries

- YAML is loaded with `Psych.safe_load`; Ruby object deserialization and aliases are disabled.
- Secret metadata provides redaction and persistence policy only. It is not encryption or protected-memory storage.
- File sources reject secret persistence unless explicitly opted in.
- Consumers remain responsible for choosing appropriate secret stores, key management and repository hygiene.
