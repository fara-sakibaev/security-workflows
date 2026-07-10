# Tooling evidence

Versions are centralized in `scripts/versions.env`. Release binaries are selected from immutable version tags and verified against the publisher's SHA-256 digest in official GitHub release metadata. Installation fails when a digest is absent or mismatched.

| Tool | Version | Role | Outputs | Exit interpretation |
|---|---:|---|---|---|
| actionlint | 1.7.12 | GitHub workflow syntax | console | nonzero is validation failure |
| ShellCheck | 0.11.0 | Shell static lint | console | nonzero is lint failure |
| PyYAML | 6.0.3 | YAML/action metadata parsing | parser result | exceptions fail validation |
| Semgrep CE | 1.122.0 | Rules and source patterns | JSON, SARIF | `--error`: 0 clean, 1 findings, other failure |
| Gitleaks | 8.28.0 | Secret patterns and history | SARIF | 0 clean; 1 is accepted as findings only with valid nonempty SARIF |
| OSV-Scanner | 2.3.8 | Dependency vulnerability authority | JSON, SARIF | 0 clean, 1 findings, 128 unsupported/no packages, other operational failure |
| Trivy | 0.70.0 | Filesystem, configuration, optional image | SARIF | explicit `--exit-code 1`; 0 clean, 1 threshold findings, other failure |
| Bandit | 1.7.10 | High-confidence/high-severity Python checks | JSON | 0 clean, 1 findings, other failure |
| cargo-deny | 0.19.4 | Project-owned Rust bans/licenses/sources policy | JSON lines | check bitset 1-15 findings; other nonzero failure |
| Psalm | project-owned; fixture 6.16.1 | PHP analysis and taint | JSON | 0 clean, 2 findings, 1/other execution failure |
| Clippy | caller Rust toolchain | Rust lint policy | Cargo JSON messages | warnings/findings are report-only; compiler failures are execution failures |

The manually verified CLI contracts come from each vendor's official documentation and built-in help for the pinned version. OSV is authoritative for dependency vulnerability gating. cargo-deny excludes advisories centrally to avoid a second Rust advisory gate. Trivy may overlap OSV but applies the public severity threshold.

## Third-party actions

| Action | Release | Immutable SHA |
|---|---:|---|
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `actions/upload-artifact` | v7.0.1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact` | v8.0.1 | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `github/codeql-action/upload-sarif` | v4.37.0 | `99df26d4f13ea111d4ec1a7dddef6063f76b97e9` |

Known limitations: vulnerability databases evolve; fixture tests assert a known package/advisory rather than an exact total. GitHub Code Scanning availability depends on repository visibility and GitHub Code Security licensing. The external-caller and fork behaviors remain release-blocking until observed on GitHub-hosted runners.
