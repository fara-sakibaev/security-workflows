# v0.1.0 release checklist

Do not recommend or tag `v0.1.0` until every item is checked with evidence.

- [ ] `actionlint` 1.7.12 passes.
- [ ] ShellCheck 0.11.0 passes.
- [ ] PyYAML 6.0.3 parses workflows and action metadata.
- [ ] Semgrep 1.122.0 validates every central rule.
- [ ] Composite action metadata and output mappings validate.
- [ ] Every scanner installation and official checksum/digest verification passes.
- [ ] All common and language fixture tests pass.
- [ ] Every normalized status is exercised.
- [ ] Generic workflow runs from a separate caller repository at a full SHA.
- [ ] Python or another language profile runs from that external caller.
- [ ] Central checkout is proven equal to `job.workflow_sha`.
- [ ] Caller checkout is proven equal to caller `github.sha`.
- [ ] Machine-readable reports are retained with no complete secret values.
- [ ] Valid SARIF uploads on an allowed event.
- [ ] Same-repository PR SARIF behavior is verified.
- [ ] Fork PR scanners run and SARIF upload is skipped.
- [ ] Dogfood workflow passes.
- [ ] No mutable or shortened third-party action references exist.
- [ ] No placeholder tests or silent mandatory-validator skips remain.
- [ ] Documentation examples match the public inputs and permissions.

Current decision: **not release-ready**. GitHub-hosted and external-caller evidence is pending.
