# Contributing

## Prerequisites

Bash 4+, Python 3, `curl`, Git, Cargo/Rust, PHP, and Composer are required. `make bootstrap` installs pinned actionlint, ShellCheck, Semgrep CE, PyYAML, Bandit, Gitleaks, OSV-Scanner, Trivy, and cargo-deny.

```bash
make bootstrap
make lint
make test
make validate
make security
```

None of these commands silently skips a mandatory check. The optional pinned-image fixture is enabled with `RUN_CONTAINER_TESTS=true make test`.

Update action SHAs and their adjacent release comments together, then update `docs/TOOLING.md`. Update scanner versions only in `scripts/versions.env`; verify release asset names, official digests, executable names, CLI help, output formats, and exit codes. Never use mutable download URLs or execute downloaded scripts through a pipe.

Semgrep changes require rule validation and focused fixture expectations. Policy changes require security review, noise analysis, documented gate impact, and release notes. Every security-impacting change must explain permissions, untrusted-code behavior, suppressions, and compatibility.
