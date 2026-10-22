# Local-workspace Bot provider delivery

**Updated status: HOLD.** Independent Rust verification of the original source
returned1 PASS/14 FAIL. A NULL/type/byte-bound repair is now implemented but has
not been re-run in Rust here. See [NULL-PROJECTION-FIX.md](NULL-PROJECTION-FIX.md)
and the preserved independent failure evidence. Earlier SQL/static results below
do not establish Rust or product acceptance.

Implemented real SQLite persistence on the existing BusinessStore connection:
strict module schema, generated persistent namespace/draft UUID registry, structured
workspace/conversation/project scope, editing_only lifecycle, canonical bounded
MYBD archive, stored revision CAS and exact original local-save receipt. No second
store, account/login credential, historical grant/token/file import or execution.
No existing remote unknown/reservation ledger is read or written by the provider.

Four typed native methods are added to actual muyon-android-ffi ProductCore.
Fixed argument order, JSON fields, failures and host late-receipt rules are in
INTERFACES.md. Core free functions are substantive implementations, not empty traits.
All registry/archive/receipt changes use one BEGIN IMMEDIATE transaction. Repeated
same intent returns its original receipt, changed parameters reject, new stale CAS
rejects, and lookup never resaves or substitutes current head for original receipt.
Read returns storage status only, never a blanket saved flag for a new editor.

## Integration dependency

Core owner alone must add `pub mod bot_drafts;` using CORE-EXPORT.patch. The patch
passes git apply --check and core lib.rs was not locally edited. Without that export,
FFI/tests importing the module cannot compile; do not enable can_save yet. Parent
must integrate this task's code plus the one-line core export and canonical host
adapter, then run Rust/UniFFI/Kotlin/Android validation. No MainActivity, ChatScreen,
ProductService, ProductChatRuntime or documents implementation was modified here.

Dependencies are fixed: base UI98baa979223d96094f11a56c3ac6d48f9b84c0eb, core
f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac (ordinary merge on this task branch),
plan/codec inspection6d61baf709f6d5a1e411ec6f24a19f357dc9a8bc. No shared task
working directories were assumed. This snapshot lacks AGENTS.md, .agents/skills
and the requested dated design master; available design index and fixed approved
provider/owner contracts were inspected. No missing document was invented.

## Evidence and limits

- Test-first source:15 Rust behavior tests plus1 FFI integration test. Initial cargo
  attempt exited127 (cargo not found), preserved in evidence/test-first.log.
- Rust compilation/tests, cargo fmt, UniFFI generation, canonical Kotlin roundtrip,
  late-callback UI behavior, Android integration: **NOT_RUN**, missing toolchain;
  core export additionally awaits sole owner. No software was installed.
- Python/SQLite executes actual extracted production DDL/DML and checks initial
  registry, unique scope, all SQL parsing/binding counts, receipt-insert fault
  rollback, CAS, restart/callback-loss durability, exact original after later save,
  lifecycle predicate, bounded archive/receipt projections and unchanged synthetic
  old unknowns/reservation: **PASS**, evidence/sql-smoke.log.
- Export patch application check and git diff --check: **PASS**. First malformed
  export patch failed check and was regenerated; failed evidence is retained in
  evidence/export-patch-first-failed.log. Owner file remained untouched.
- Independent reviewer found three low issues; all repaired and rechecked. See
  REVIEW.md. No high/medium issue found; review was static, not test acceptance.
- Re-run evidence script from repo root:
  `python3 docs/tasks/local-workspace-bot-provider-20261022/evidence/verify.py`.

Checksums detect corruption only. There is no claim of data authentication or
resistance to adversarial whole-database rollback. All fixtures are synthetic;
no real user files or real model/search/network execution endpoints were used.
Remote activity is limited to authorized source fetch and task-branch push.
