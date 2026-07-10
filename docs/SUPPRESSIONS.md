# Suppressions

A suppression is acceptable only after confirming a false positive or a documented non-exploitable condition. It must be narrow, reviewed, and time-bounded.

Record the finding identifier, owner, reason, creation date, expiry date, and exact scope in `.security/suppressions.yml`. Broad path exclusions and permanent wildcard suppressions are dangerous because they hide future unrelated findings.

Semgrep suppressions should use narrow native rule/path mechanisms or a reviewed project-local rule. Gitleaks accepts additive `[[allowlists]]` entries only; include a description and constrain paths/commits/regexes. OSV supports `IgnoredVulns` with `reason` and `ignoreUntil` in project-native configuration, but this workflow currently does not override per-lockfile native OSV configuration. cargo-deny and Psalm use project-owned policy files.

Example metadata:

```yaml
suppressions:
  - id: GHSA-example
    owner: application-security
    reason: Vulnerable optional feature is not compiled
    created: 2026-07-10
    expires: 2026-08-10
    scope: Cargo.lock
```
