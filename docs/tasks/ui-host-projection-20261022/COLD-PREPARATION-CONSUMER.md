# Fixed five-method cold-start consumer checkpoint

Fixed schema source098d9aca214e6642c1b3ffde64921ebedbae335d; read INTERFACES,
SAVE-PREPARATION-INTERFACE and SAVE-PREPARATION-REPORT without guessing wire fields.
Existing four Service methods/verified generated binding remain connected. Fifth
Service method currently explicitly unavailable until B releases actual fifth
binding; exact unapplied NATIVE-PREPARE-SERVICE.patch is ready. verified=false.
No missing-generated-method symbol, reflection, fake ProductCore or auto-save fallback.

## Actual consumer behavior

Host captures canonical MYBD archive with NEXT STORED revision, original live reducer
instance, scope, actual registry binding, memory/editor revisions, digest and local
save-attempt UUID. Native prepare receives that exact archive and must acknowledge
ALL fields/state=prepared before the exact existing save is dispatched. Prepare
error, malformed/foreign acknowledgement or lost reply means ZERO save calls and
original-only hold. No editor/grant/created/fee result is supplied as authority.

Strict descriptor accepts new save_attempt=null|exact typed durable pointer; strict
new receipts require host_editor_revision (legacy receipts are not rebound). Both
resolve AND read discover the real pointer. Race resolve(null)->read(prepared) keeps
that exact original, disables new prepare/save/restore, and never substitutes a new
host-generated attempt for the one native actually disclosed. Restore validates its
second actual read before replacing the editor, closing the analogous race.

Open/read/revalidate/save NEVER implicitly call lookup. The ONLY outcome lookup is
explicit query_original_save. It may atomically fence original prepared to
not_committed: this is local reconciliation, not pure read. A missing receipt, failed
read/lookup, malformed response or native exception never proves noncommit. No
native save is retried/replayed from a discovered pointer. Terminal outcomes are
monotonic: committed cannot become not_committed or vice versa. Full known terminal
binding is retained, not just its attempt ID; conflicting digest/editor fields fail.

A confirmed not_committed_local_storage releases only that original hold and permits
a NEW explicit user save/prepare. A committed live receipt acknowledges only the
original mounted export: later editor or reducer changes stay unsaved. Cold pointer
lookup NEVER acknowledges the current/new reducer, even if memory/editor counters
are numerically equal (explicit0/0 regression). It releases recovery hold, exposes
historical result through the existing persistence state, and requires explicit
canonical restore before saving over an existing archive. Restore resets all old
capabilities/creation authority via sole Bot codec; it is never saved acknowledgement.
Repeated saved editor commands do not prepare/save again; pending repeat does not
implicitly execute lookup either. Stale scope/generation rejection returns no editor.

No new on-disk Kotlin file store, account ACL, authorization grant, execution gateway,
Agent creation, old unknown ledger or fee state was added. Ownership remains actual
local_workspace+live project from BusinessStore and private app-issued conversation.

## Checks and honest acceptance boundary

Test-first native-preparation-red.log records missing prepare port override before
implementation. Terminal-state negative test executed RED at
native-preparation-terminal-red.log; two independent intermediate reproductions
were retained (terminal reversal accepted, read pointer dropped), followed by fixed
outputs. Read race tests were added with the implementation, not relabelled as TDD.

Actual commands (real Kotlin2.2.20 + org.json, no Android/generated stubs):

```
export KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc
export JSON_JAR=/workspace/host-projection-tools/json.jar
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-codec.sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-session.sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
```

PASS raw evidence/native-preparation-{codec-green,green,runtime-regression}.log.
Non-author actual three-runner PASS and terminal/read-race fixed repro outputs are
native-preparation-*-independent*.log. Review's two findings were fixed; final static
review has no Important. The final tiny duplicate-saved guard is also exercised by
our final session rerun (prepare/save counts stay1), rather than claiming an old log
was re-executed after that guard. Final source still awaits real Android compilation.

Fetched/read parent c4bc82b60f919eeedb7e466279efb783bc31a562
SAVE-PREPARATION-RUST-VERIFICATION: exact owner098 plus sole export b0d3 and pure-fmt
111e51178645bdcf147a8a24a0caf3a76755db39 actually provider26/core209(includes26)/
3 independent probes pass; formatted fmt0. Its fifth FFI attempt could not compile
for missing offline anyhow; B's separate actual fifth-method compilation/generation
is still pending. Earlier four-method FFI pass does NOT verify new preparation API.
Those are upstream results, not this thread's fresh Rust run. No old RED is rewritten.

Production verified/can_save remains disabled until actual five-method native/binding
composition and Host/Android gates pass; there is no unconditional bool flip. The
cold-consumer code above is implemented/tested with synthetic boundary ports, not
advertised as a running Android persistence feature. Reader native/PFD and annotation
original-intent bridge remain separate unfinished tasks, with exact requests already
in READER-FFI-MINIMAL-SCHEMA.md; this batch does not claim them completed.

## Shell additive history field (same schema_version1)

original_save_outcome is null until a verified original outcome exists, then:
status=committed_local_storage|not_committed_local_storage, attempt_id,
expected_stored_revision, proposed_stored_revision, committed_stored_revision
(null for noncommit), exported_memory_revision, host_editor_revision, historical=true,
cold_recovered Boolean, acknowledges_current_editor Boolean. All revisions are
canonical decimal strings, no fake actual fee/execution fields. It is historical
receipt metadata; only committed+same live export/current memory+editor+instance
may acknowledge current editor. Cold always false, even equal revision numbers.
Query supplies this fact while saved=false; explicit restore stays separately offered.
A proposed next revision from a fenced attempt is NEVER exposed as committed storage.
History projection test-first native-preparation-history-red.log records missing
lastOutcome before implementation; final Runtime cold instance test verifies no
open lookup, explicit outcome metadata, ack=false, then explicit restore(saved=false).

Final non-author three-runner re-execution including history and duplicate guard:
all exit0. Raw evidence/native-preparation-history-{codec,session,runtime}-independent-final.log.
Final reviewer: no Important; actual Runtime synthetic-port verification only,
not fifth FFI/native/Android acceptance. Earlier raw independent outputs retained
separately; no red evidence was replaced by final green.
