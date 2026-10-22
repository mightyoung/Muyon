> Historical first-batch record for 4eec6d16. Current continuation and fulfilled historical-hook integration: [WORKFLOW-REPORT.md](WORKFLOW-REPORT.md). Original evidence below is preserved.

# MIG17 / U12 — reviewable backend source, integration HOLD

Branch: `task/artifacts-mig17-u12-20261022`.
Fixed core dependency: `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac`.
UI reference read only: `98baa979223d96094f11a56c3ac6d48f9b84c0eb`.
Design specification read from fixed `400e206135690c284c8402521e3135cfb7bfaee8`.
No AGENTS.md/.agents/skills was found in the checked snapshots/workspace ancestors.

## Delivered

`crates/muyon-core/src/artifacts/` contains actual BusinessStore-backed code:

- Explicit initial archive of an existing canonical output document under a
  project/artifact identity. No chat deletion callback or generated auto-save.
- Immutable artifact revisions, source DocumentMetadata snapshots and separate
  creator/editor provenance using the existing Human/Ai author contract.
  Generated origin retains agent/run and optional message/attempt identity.
- Revision publication and blob/document publication share the existing SQLite
  transaction, exact document CAS, artifact CAS and persisted grant tail checks.
- Sticky human-edit protection: generated publication after any human revision
  returns IntentConflict, including when its CAS is fresh. Human changes keep
  source snapshots and initial creator; no automatic rebase or overwrite occurs.
- Restart lookup of exactly authorized saved revisions, bounded history paging,
  canonical metadata comparison and SQL-side payload size limits.
- Every output/source access consults current stored grants, project liveness,
  scope, exact document revision and epoch/generation/expiry. Sources are distinct
  and same-project; no model-provided permission or filesystem path is accepted.

Artifacts contain no second document body/blob/grant truth. The canonical
output is a registered document; archive does not create/register that document.
Subsequent revise takes a real FinishedBlob upload and publishes via the existing
core hook. An engine is not enabled by this metadata catalog.

Public methods on BusinessStore:

```text
initialize_artifacts_trusted()
archive_artifact_trusted(id, output_access, source_accesses, origin)
revise_artifact_trusted(id, expected_artifact_revision, output_access,
                       finished_blob, title, current_source_accesses, origin)
read_artifact_revision(id, revision, output_access, current_source_accesses)
artifact_history(id, exclusive_before_revision, limit_1_to_32,
                 output_access, current_source_accesses)
```

Origin must come from the authenticated host actor/run, never generated JSON.
Only an explicit user save operation should invoke archive/revise. These APIs
are not exposed through a model/tool dispatcher. Initial archive needs current
ReadText+StructuredEdit on output, and ReadText on every source.

## Review correction and remaining blockers

Independent review identified that a newer revision grant cannot authorize an
older snapshot. Corrected output/source comparisons to exact DocumentRef. The
stored history remains immutable, but reading a changed output/source returns
RevisionConflict instead of silently following its latest revision.

Required owner actions are specified in [CORE-HOOKS.md](CORE-HOOKS.md):

1. Core owner adds `pub mod artifacts;` in lib.rs. No owner file was edited.
2. Core owner implements real historical revision authorization under live host
   policy; existing publication-tail grant validation is not historical read
   authority. Until then, historical content after output/source advance remains
   HOLD. A page containing inaccessible content fails atomically.
3. Project-level authorized artifact discovery and host/UI wiring remain
   NOT_IMPLEMENTED. A single document grant cannot enumerate an entire project.
4. The host must retain original intent/result recovery semantics. A storage
   commit error is not a success receipt; look up the original save state before
   retrying. This module does not replace the existing gateway receipt system.

Ordinary forms/reactions may reuse typed commit/result UI plumbing only after
routing to their actual business owner. Artifact save is not a universal form
submit receipt, a feedback system, or evidence those flows were implemented.

No real PDF engine/render/edit fidelity, Android integration, APK or device
acceptance is claimed. Restoring metadata never restores bytes into the current
head. Actual byte delivery must enforce current/historical authority at use.

## Validation

Tests were authored before implementation; initial execution was attempted and
preserved. No verified Rust red/green cycle was possible in this environment.
Six real BusinessStore/blob test cases were written using only synthetic PDFs,
projects and actors in temporary directories:

- Restart recovery; exact frozen source identity; source advance denial.
- Atomic human revision, generated-overwrite rejection, stale artifact CAS.
- Revocation, project deletion, wrong output and missing source denial.
- Duplicate sources, invalid schema, payload size limit and bad page size.
- Actual SQL trigger failure after document publication; both heads roll back.
- Cross-project source, missing write permission, epoch/generation/expiry denial.

| Check | Actual result |
|---|---|
| Initial cargo targeted test attempt | NOT_RUN, exit 127, cargo absent |
| Post-implementation cargo targeted attempt | NOT_RUN, exit 127, cargo absent |
| Isolated targeted/full offline Rust tests and rustfmt harness | NOT_RUN, exit 127, cargo absent |
| Independent actual DDL round-trip on disk SQLite | PASS |
| Independent u64 revision ordering/exclusive page cursor SQL | PASS |
| Independent trigger failure / transaction rollback SQL | PASS |
| Python harness compile | PASS |
| git diff --check / staged whitespace check | PASS |

`verify_offline.py` copies the tracked repository (including test fixtures) and this
module to a disposable directory, adds the lib.rs export only in that copy, and
runs targeted tests, full Rust workspace tests and rustfmt check. It never edits
the real owner-controlled lib.rs. Run in an authorized environment with the
existing pinned toolchain/dependencies; it performs no installation.

Independent SQL checks exercise extracted real Rust DDL/query strings, not the
Rust permission/blob methods. Static review found no confirmed additional
compile defect; compilation remains unverified. See [independent review](INDEPENDENT-REVIEW.md)
and raw logs under `evidence/`. Missing Rust tools are environment blockers, not
a denial or a test failure reported as passing.

## Scope custody

Changed paths are confined to new artifacts/** and this task's docs. No changes
to documents/**, lib.rs, Android shell or host owner files. No main/develop
modification, force push, deletion, deployment, dependency installation, paid
configuration, credential change or security permission expansion. No real
model/search request, user file or original unknown/reservation was touched.

This is source delivery for designated-owner integration, not full U12 product
completion or permission to bypass engine isolation HOLD.
