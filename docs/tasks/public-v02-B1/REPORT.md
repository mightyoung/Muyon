# Public v0.2 B1 domain projections

Base: `e16af808620488a7be0b3b4a10b91190d18f1177`.
Branch: `task/public-domain-projections-b1-20261024`.

Read-only projections preserve the existing research/business stores. No migration, dispatch, Reader, service contract, FFI or UI changes.

## API

```rust
fn project_paper(paper: &PaperRecord, scope: &ScopeRef, documents: &[DocumentRef]) -> Result<ResearchView, ServiceError>;
fn project_supplier(supplier: &SupplierRecord, scope: &ScopeRef, documents: &[DocumentRef]) -> Result<SupplierView, ServiceError>;
```

The parent approved adding `scope` to the plan's candidate `project_paper` signature: PaperRecord has a project but no workspace, so the original signature could not reject a different workspace carrying the same project ID. Both scopes and records must originate in the trusted host's current authorized read. These functions check consistency and do not issue authority. Every supplied DocumentRef must match the complete host workspace/project scope; paper.project_id must also match. The host supplies the current record-to-document association; paths, blob IDs and digests cannot establish that association. Opening documents still requires the document service's authorization recheck.

DocumentBindingView is defined in research_projection and reused by inquiry_projection. It never copies document bytes. Without mappings, research emits one Unbound per known attachment, or an empty list for no attachments. SupplierRecord has no attachment metadata: its empty mapping produces Unbound to report binding unavailability only, without claiming an attachment exists. Deleted suppliers are rejected. Views copy only declared display fields and exact Revision values; raw JSON, unrelated supplier notes, blob metadata and internal paths are absent.

## Verification and pending integration

Evidence directory: `/workspace/muyon-contracts-evidence/` (local logs).

| Stage | Exit | Result | Evidence |
| --- | --- | --- | --- |
| Baseline research/business | 0 | see counts below | b1-baseline.log |
| Structure RED | 101 | missing projection modules | b1-structural-red.log |
| Behavior RED | 101 | 0 passed, 4 failed at unavailable stubs | b1-behavior-red.log |
| Behavior GREEN | 0 | 4 passed, 0 failed | b1-green.log |

The four tests cover shared references, absent mappings and attachment counts, exact revisions including u64::MAX and values above 2^53, serialization round trip and secret-field exclusion, every supplied reference's scope, paper/host project mismatch, invalid scope and deleted suppliers.

Pending: root-owned module registration, switch tests from temporary path-loading to actual public exports, final full workspace all-targets tests, Clippy, fixed-SHA independent review. No push or PR yet. This report will be completed after those checks.

Ledger lives outside the worktree because .superpowers is not ignored; no shared ignore rules were changed.
