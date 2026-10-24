# Public v0.2 B1 domain projections

Base: `e16af808620488a7be0b3b4a10b91190d18f1177`.
Implementation: `8934ba383c3cf62d818d13f6276768104853621f`.
Root-owned module registration: `5f45b6ab6549c504925d143c0e5677d9cbe1fa01`.
Fixed final source/test SHA: `18a4e8b7d831c5bb6b1fb2e6b24e97dbe1e113e1`.
Branch: `task/public-domain-projections-b1-20261024`.

Read-only projections preserve the existing research/business stores. No migration, dispatch, Reader, service contract, FFI or UI changes.

## API

```rust
fn project_paper(paper: &PaperRecord, scope: &ScopeRef, documents: &[DocumentRef]) -> Result<ResearchView, ServiceError>;
fn project_supplier(supplier: &SupplierRecord, scope: &ScopeRef, documents: &[DocumentRef]) -> Result<SupplierView, ServiceError>;
```

The parent approved adding `scope` to the plan's candidate `project_paper` signature: PaperRecord has a project but no workspace, so the original signature could not reject a different workspace carrying the same project ID. Both scopes and records must originate in the trusted host's current authorized read. These functions check consistency and do not issue authority. Every supplied DocumentRef must match the complete host workspace/project scope; paper.project_id must also match. The host supplies the current record-to-document association; paths, blob IDs and digests cannot establish that association. Opening documents still requires the document service's authorization recheck.

DocumentBindingView is defined in research_projection and reused by inquiry_projection. It never copies document bytes. Without mappings, research emits one Unbound per known attachment, or an empty list for no attachments. SupplierRecord has no attachment metadata: its empty mapping produces Unbound to report binding unavailability only, without claiming an attachment exists. Deleted suppliers are rejected. Views copy only declared display fields and exact Revision values; raw JSON, unrelated supplier notes, blob metadata and internal paths are absent.

## Verification

Evidence directory: `/workspace/muyon-contracts-evidence/` (local logs).

| Stage | Exit | Result | Evidence |
| --- | --- | --- | --- |
| Baseline research/business | 0 | business 14, research 16 passed | b1-baseline.log |
| Structure RED | 101 | missing projection modules | b1-structural-red.log |
| Behavior RED | 101 | 0 passed, 4 failed at unavailable stubs | b1-behavior-red.log |
| Behavior GREEN (temporary path imports) | 0 | 4 passed, 0 failed | b1-green.log |
| Research/business regression | 0 | business 14, research 16 passed | b1-regression.log |
| Actual public export GREEN and regression | 0 | projections 4, business 14, research 16 passed | b1-public-green-regression.log |
| Workspace all-targets serial tests | 0 | 724 passed, 0 failed, 0 ignored; 47 result blocks | b1-workspace.log |
| Workspace all-targets Clippy, warnings denied | 0 | clean | b1-clippy.log |
| Lock/cache SHA-256 verification | 0 | 103/103 registry archives match current lock | b1-cache-check.log |

The four tests cover shared references, absent mappings and attachment counts, exact revisions including u64::MAX and values above 2^53, serialization round trip and secret-field exclusion, every supplied reference's scope, paper/host project mismatch, invalid scope and deleted suppliers.

Root registered only the two modules, retaining development. Tests now import actual `muyon_core::domains` exports. Commands used Rust/Cargo 1.93.1, sourced `/workspace/muyon-contracts-tools/env.sh` and overrode `CARGO_TARGET_DIR=/workspace/muyon-contracts-tools/b1-target`:

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_domain_projections --test research --test business
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- -D warnings
```

Earlier structural/behavior RED and initial GREEN used the same focused command with only `--test public_domain_projections`; baseline and separate regression used `--test research --test business`. No dependencies were downloaded or installed. Cargo.lock was unchanged, SHA-256 `d5e34dfe4b3cf2be3a5d944c9843ed2aee6c3ec4a8932f03bb86bf9ceedb75b1`.

## Independent review

Fresh-context read-only review of the complete immutable range `e16af808620488a7be0b3b4a10b91190d18f1177..18a4e8b7d831c5bb6b1fb2e6b24e97dbe1e113e1` found no Critical or Important issues and independently reproduced focused tests (exit 0, 4 passed, 0 failed). Full local artifact: `/workspace/muyon-contracts-evidence/b1-independent-review-18a4e8b7.md`. The reviewer inspected broad logs but did not rerun the full workspace or recreate historical RED runs. One Minor noted stale pending checks in the original report; this report finalization supplies actual counts, commands, scope and fixed source SHA. No deferred code findings remain.

Review dispositions (each item the reviewer declined to judge):

| Boundary | Ruling and remaining cost |
| --- | --- |
| Host authorization, account/generation freshness, revocation | Keep host-owned preconditions; no host integration claimed. A host that bypasses authorization can supply unauthorized metadata. |
| Same-scope association provenance | Host must map record to reference; metadata alone cannot prove association. Incorrect host mappings can display an unrelated reference. |
| Partial nonempty mappings | Flat slice exposes supplied mappings only, without per-attachment completeness claims. Partial correspondence needs a future explicit host contract; no blob matching is guessed here. |
| Supplier attachment count/project ownership | Record has neither; retain host scope and availability-only Unbound. No attachment existence/count can be inferred. |
| Views as authority and display text | Display DTOs grant no authority. Title/name remain domain display text; host validation and UI rendering remain their owners' responsibilities. |
| Document opening/bytes/history/lifecycle/Reader | No such changes or verification claimed; opening must independently recheck document access. |
| UI/FFI/plugin conformance/quote rules/writes/migrations/end-to-end | Outside authorized B1. These features remain unimplemented/unverified by this slice. |
| Hostile collection sizes/resource limits | Typed host-loaded inputs are the boundary; no new untrusted decoder is added. Future untrusted consumers need resource bounds. |
| Existing store correctness/dependency behavior/external spec links | Existing types were inspected for local compatibility; no claim of a full dependency audit or external design verification. |
| Changes after reviewed source SHA/publication | This final change is documentation only. Push, Draft PR and any later code changes require root's separate verification. |

No push or PR yet; root retains publication responsibility. UI, native rendering, permission acquisition, document opening and live host mapping integration were not exercised. No denied operations or execution blockers remain.

Ledger lives outside the worktree because .superpowers is not ignored; no shared ignore rules were changed.
