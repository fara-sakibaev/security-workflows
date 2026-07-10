# Versioning

This repository uses semantic versioning after runtime evidence exists.

- Patch: compatible fixes, documentation corrections, and scanner database-independent tuning.
- Minor: additive inputs, profiles, checks, or reports that preserve the public contract.
- Major: removed/renamed inputs, changed types/defaults, status-contract changes, or materially incompatible gates.

The first candidate is `v0.1.0`, not `v1.0.0`. It must not be recommended until [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) is complete in GitHub-hosted execution.

Tags are for discoverability. Callers pin the full commit SHA corresponding to a reviewed release. Dependabot or Renovate should propose SHA updates with the human-readable release in the comment; updates require review of scanner, permission, and gate changes.
