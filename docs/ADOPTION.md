# Adoption

Every caller must pin `FULL_COMMIT_SHA` and explicitly grant the permission ceiling. The reusable workflow cannot elevate a caller token.

Use this job and change only `profile` for the supported stacks:

```yaml
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
      profile: generic # php | rust | python | typescript
      fail_on_severity: high
      upload_sarif: true
      run_semgrep: true
      run_language_analysis: true
      working_directory: .
```

Generic uses `profile: generic`. PHP/Symfony uses `profile: php` and should commit `composer.lock`, `psalm.xml` or `psalm.xml.dist`, and `vimeo/psalm` as a development dependency. Rust uses `profile: rust`, commits `Cargo.lock`, and optionally owns a cargo-deny configuration. Python uses `profile: python` and should prefer a resolved lock (`poetry.lock`, `Pipfile.lock`, `pdm.lock`, `pylock.toml`, or `uv.lock`); fully pinned `requirements.txt` is supported with the documented limitation. TypeScript/Node uses `profile: typescript` with `package-lock.json`, `pnpm-lock.yaml`, or `yarn.lock`.

Copy-paste profile values:

```yaml
# Generic
with:
  profile: generic
  working_directory: .
```

```yaml
# PHP / Symfony
with:
  profile: php
  working_directory: .
```

```yaml
# Rust
with:
  profile: rust
  working_directory: .
```

```yaml
# Python
with:
  profile: python
  working_directory: .
```

```yaml
# TypeScript / Node.js
with:
  profile: typescript
  working_directory: .
```

Container scanning uses an existing image and never builds one:

```yaml
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
      scan_container: true
      container_image: registry.example/service@sha256:FULL_IMAGE_DIGEST
      upload_sarif: true
```

Recommended events are `pull_request`, push to the default branch, and weekly schedule `17 3 * * 1`. Fork PRs scan read-only and skip SARIF upload. Same-repository PRs upload when permitted. If SARIF is disabled, callers may omit `security-events: write`, but nested permission behavior must be verified in the consuming repository before relying on that reduced example.

Do not use `@main` or a release tag. See [INTEGRATION_TESTING.md](INTEGRATION_TESTING.md) before first adoption.
