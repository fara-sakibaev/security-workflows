# Architecture

## Boundaries

`reusable-security.yml` is the public API. It validates typed inputs and explicitly dispatches to one profile workflow. Profile workflows are static references because GitHub does not permit expressions in reusable-workflow `uses` paths.

`reusable-generic.yml` owns the common baseline, report artifact, SARIF upload, and common gate. Language workflows invoke that baseline and add one read-only language-analysis job. Composite actions wrap repeated installation, report production, and normalized output behavior; policy orchestration remains visible in workflows.

## Repository identity and checkout

Reusable workflows execute in the caller's event context. `github.sha` identifies caller code and is never used as the central repository revision.

Each scanner runner independently:

1. Reads `job.workflow_repository` and `job.workflow_sha` from the job context.
2. Checks out caller code at `github.sha` into `workspace/`.
3. Checks out this repository at the exact job workflow SHA into `security-platform/`.
4. Asserts both checked-out Git SHAs.
5. Resolves and bounds `working_directory` below `workspace/`.

Absolute paths are never passed between jobs because runner filesystems are isolated. The job identity properties are currently GitHub.com-only.

## Permissions and reports

Read-only scan jobs upload redacted/machine-readable reports as five-day artifacts. A separate job downloads and validates SARIF before calling the official GitHub upload action. Only that job has `security-events: write`. Fork pull requests skip it while retaining scans.

Stable categories are `gitleaks-content`, `gitleaks-history`, `osv`, `trivy-vulnerabilities`, `trivy-misconfiguration`, `trivy-image`, and `semgrep`. Bandit and Psalm are retained as JSON because this implementation has not locally proven valid SARIF for the pinned invocation.

## Policy ownership

Central configuration is authoritative and project configuration is additive. Native scanner suppression mechanisms are used where they can preserve the baseline. This repository normalizes execution state but does not define a vulnerability schema, risk score, scanner engine, or aggregation service.
