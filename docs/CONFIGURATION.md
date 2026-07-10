# Configuration

## Public workflow inputs

The public inputs and defaults are defined in `reusable-security.yml` and summarized in the README. Enum strings, image references, and caller paths are validated before profile dispatch. `working_directory` rejects absolute paths, backslashes, control characters, and `..` segments.

`fail_on_severity` controls Trivy's reported and blocking severities. OSV-Scanner does not provide a reliable universal severity filter for every ecosystem/advisory, so every OSV vulnerable-package finding blocks. This is explicit rather than pretending unknown severity is low risk.

## Project-owned configuration

```text
.security/
├── gitleaks.toml
├── policy.yml
├── semgrep/
└── suppressions.yml
```

- `.security/semgrep/*.yml`: additive rules. Empty directories leave central rules active. Malformed rules produce `scanner-execution-failure`.
- `.security/gitleaks.toml`: only additive `[[allowlists]]` entries are accepted. Each entry must have a description. Rules, disabled rules, and replacement configuration are rejected.
- `deny.toml`, `cargo-deny.toml`, or `.config/deny.toml`: project-owned cargo-deny policy. If absent, status is `not-configured`.
- `psalm.xml` or `psalm.xml.dist`: project-owned Psalm policy. A Composer-installed `vendor/bin/psalm` is required.
- `.security/policy.yml` and `.security/suppressions.yml`: review metadata only; they are not a custom suppression engine.

## Container images

The workflow never invents a build command. `scan_container: true` requires `container_image`. For reproducibility, consumers should use a digest reference such as `registry.example/image@sha256:...`.
