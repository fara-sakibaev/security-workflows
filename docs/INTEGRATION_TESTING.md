# External caller verification

Repository-local dogfood cannot prove cross-repository paths. Before `v0.1.0`, create a temporary or dedicated caller repository under an owner allowed to access this repository.

1. Push the candidate commit and record its full 40-character SHA.
2. Copy `test-fixtures/external-caller` into a separate repository.
3. Replace `OWNER` and `FULL_COMMIT_SHA` without changing the `uses` shape.
4. Enable Actions access to this reusable workflow repository if it is private.
5. Run the generic workflow and the Python workflow.
6. Confirm logs show central checkout at the candidate SHA and caller checkout at the caller SHA.
7. Confirm JSON/SARIF artifacts exist and allowed-event SARIF uploads succeed.
8. Open a same-repository PR and a fork PR. Confirm both scan; only the fork skips upload.
9. Record run URLs and results in the release checklist.

The caller must literally use:

```yaml
uses: OWNER/security-workflows/.github/workflows/reusable-security.yml@FULL_COMMIT_SHA
```

Relative workflow calls do not satisfy this test. This procedure is implemented but has not yet been executed from this workspace.
