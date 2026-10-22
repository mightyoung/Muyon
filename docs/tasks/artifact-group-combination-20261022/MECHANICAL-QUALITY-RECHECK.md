# Mechanical follow-up, explicit parent scope

Fixed code 8bccaaed2801365f8dba4b9de7d7bddeb23c8e1b, based863ece54.

- 55fddbbc3bc87f4cadc46033aa2d29e3d9ea13c2: exactly one non-Drop drop(g)
  removed from document_edit_core_bridge.rs. Journal holds &BusinessStore only,
  no Drop; all assertions/drop(s)/restart ordering retained.
- 8bccaaed2801365f8dba4b9de7d7bddeb23c8e1b: rustfmt1.93.1 edition2021
  skip_children=true on the85 product crate Rust files changed vs develop. Each
  original formatted in an independent /tmp tree, then formatted repository bytes
  compared exactly;12 files changed. No labs, evidence copies, UI/source branches.
- Independent reviewer checked fixed diff and exact outputs: no behavior, fields,
  signatures or lint annotation changes. Worker modules/exports retained.
- Product packages cargo fmt -p muyon-core -p muyon-android-ffi --check PASS0.
- All-target strict FAIL101 only reached corelib: group_runtime/store.rs460
  group_consume_and_verify_tail and bridge.rs431 group_ui_workflow, both8/7.
  No local allow/refactor; parent assigns typed redesign to original owner.
- Worker unused CandidateState/CandidateStatus reexports cannot safely be simply
  removed: actual document_edit core_bridge and candidate tests consume these
  public names. They are unused only in standalone non-test worker projection.
  No API deletion, module bypass, test removal or new lint suppression used.
  This remains unresolved behind corelib lint failure; do not call strict green.

Accurate imported Artifact exception: save_journal.rs192
#[allow(clippy::too_many_arguments)] on journal_pending (function193). This is
source-supplied, not added by integrator and distinct from FFI ABI exception and
inherited artifact_save_execute allowance. No reason text is attached in source.
From implementation, it shares Artifact/Local journal insertion with domain,
intent, project, actor, digest, json and object_id plus self (8items). That describes
the parameter source, not parent approval of suppression. Kept explicitly pending
parent acceptance or owner typed request cleanup; no global allow introduced.

Full offline locked workspace/all-target regression PASS0 at this fixed source:
763 executions, 0 failures/ignored, 31groups; all relevant candidate bridge,
Artifact and Group targets included. This is a repeat, not additional763 cases. Original failures remain in evidence, never relabeled as passes.
No publication, verified, Reader display lease, credential/network or Android change.

Full workspace cargo fmt --all --check FAIL1; every remaining diff is in
unchanged historical experiments/ (see mechanical-fmt-remaining.json), no remaining
product crates diff. Historical lab formatting is not silently bundled here.
