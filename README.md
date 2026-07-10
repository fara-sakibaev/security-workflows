# Security Workflows

Versioned reusable GitHub Actions workflows for repository security scanning. This repository orchestrates established scanners; it is not a vulnerability database, hosted service, or custom scanner.

## Release status

The implementation is pre-release. Local validation and scanner fixtures are implemented, but `v0.1.0` remains blocked until the external-caller, GitHub-hosted SARIF, fork pull-request, and dogfood checks in [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) pass. No `v1.0.0` release is planned.

## Profiles

| Profile | Common baseline | Additional analysis |
|---|---|---|
| `generic` | Gitleaks, OSV-Scanner, Trivy, Semgrep CE | None |
| `php` | Common baseline with PHP rules | Project-local Psalm and Psalm taint analysis |
| `rust` | Common baseline with Rust rules | Clippy and configured cargo-deny policy |
| `python` | Common baseline with Python rules | Bandit |
| `typescript` | Common baseline with TypeScript rules | None |

OSV-Scanner is the dependency-vulnerability authority. Trivy dependency findings provide a severity-filtered second view and may overlap. Gitleaks is the only secret scanner enabled by default; Trivy secret scanning is disabled.

## Quick start

Callers must pin the reusable workflow to a reviewed full commit SHA. A caller cannot grant permissions from inside a reusable workflow, so SARIF callers must grant both permissions explicitly.

```yaml
name: security
on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "17 3 * * 1"

permissions:
  contents: read
  security-events: write

jobs:
  security:
    uses: OWNER/security-workflows/.github/workflows/reusable-security.yml@FULL_COMMIT_SHA
    permissions:
      contents: read
      security-events: write
    with:
      profile: generic
      fail_on_severity: high
      upload_sarif: true
      working_directory: .
```

Never use `@main`, a release tag, or a shortened SHA in a caller. Release tags are discovery labels; callers pin the corresponding commit.

## Public inputs

| Input | Type | Default | Meaning |
|---|---|---|---|
| `profile` | string | required | `generic`, `php`, `rust`, `python`, or `typescript` |
| `fail_on_severity` | string | `high` | Trivy threshold: `low`, `medium`, `high`, or `critical` |
| `upload_sarif` | boolean | `true` | Upload valid scanner SARIF with the official CodeQL action |
| `scan_container` | boolean | `false` | Scan an existing image; no generic build is attempted |
| `container_image` | string | empty | Image reference required when container scanning is enabled |
| `run_semgrep` | boolean | `true` | Run central and additive local Semgrep rules |
| `run_language_analysis` | boolean | `true` | Run profile-specific optional analysis |
| `working_directory` | string | `.` | Relative caller path; absolute and traversal paths are rejected |

## Status and gates

Machine-readable action outputs use only:

- `passed`
- `findings-detected`
- `unsupported-repository`
- `not-configured`
- `scanner-execution-failure`

Gitleaks findings, OSV findings, Trivy findings at the configured threshold, Semgrep baseline findings, and mandatory scanner execution failures block. Missing cargo-deny/Psalm policy is `not-configured`; language findings follow documented project-owned policy where applicable.

## Reports and pull requests

Scanner jobs have only `contents: read`. Redacted reports are retained for five days and transferred to a separate SARIF job. Same-repository pull requests may upload SARIF when the caller grants `security-events: write`. Fork pull requests still run scanners but skip the write-capable upload job. Missing permissions or code-scanning availability cause the official upload action to fail; HTTP errors are not converted to success.

## Central and local policy

Every scanner job checks out caller code into `workspace/` and this repository into `security-platform/`. The central checkout uses `job.workflow_repository` and `job.workflow_sha`, then asserts the resulting Git SHA. This feature currently targets GitHub.com because those job identity properties are not available on GitHub Enterprise Server.

Project-owned extensions are described in [docs/CONFIGURATION.md](docs/CONFIGURATION.md). Semgrep rules are additive under `.security/semgrep/`. Gitleaks accepts additive `[[allowlists]]` only in `.security/gitleaks.toml`; local configuration cannot replace or disable the central baseline.

## Local development

```bash
make bootstrap
make lint
make test
make validate
make security
```

Required tooling is pinned. Commands fail when a required validator is unavailable. The optional pinned-container fixture runs with `RUN_CONTAINER_TESTS=true make test`.

## Limitations

Scanners have false positives and false negatives. They do not establish runtime exploitability, secure authorization, tenant isolation, business-logic correctness, or secure system design. A successful run does not prove that a repository or application is secure.

See [docs/ADOPTION.md](docs/ADOPTION.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md), and [docs/TOOLING.md](docs/TOOLING.md).
