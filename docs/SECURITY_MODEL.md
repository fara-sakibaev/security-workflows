# Security model

Gitleaks detects strings matching secret patterns in current content and available Git history. Redaction reduces disclosure in reports, but detection is heuristic and cannot establish whether a credential is active.

OSV-Scanner maps resolved dependency information to public advisories. Results depend on supported files and advisory data. An unresolved manifest is not equivalent to a lock file, and OSV output does not reliably identify direct versus transitive dependencies for every package manager.

Trivy reports severity-filtered filesystem vulnerabilities, configuration/IaC findings, and explicitly requested image findings. Secret scanning is disabled to avoid duplicating Gitleaks.

Semgrep CE runs a small reviewed pattern baseline plus additive project rules. Pattern analysis can miss data-flow and framework behavior and can report false positives.

Psalm, Clippy, cargo-deny, and Bandit add language-specific evidence. Missing project policy is distinct from a clean result. Build-oriented tools may execute package-manager or compiler behavior from caller code, but their jobs have read-only repository permissions and receive no inherited secrets.

Multiple layers are required because each observes a different artifact and failure mode. Even together they cannot establish secure business logic, authorization invariants, tenant isolation, runtime configuration, operational controls, or exploitability. Passing scans do not prove security.
