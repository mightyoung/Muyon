> Historical RED record at e5aaf8ddfa6c4cf8f467595cea1de4b431dcba05.
> Final gateway repair and exact dependency validation: see FINAL-HANDOFF.md.
> Original raw failures below are preserved and remain historical failures.

# REPRODUCTION ONLY — receipt tail notification loss remains RED

Branch task/document-source-tail-20261022, based exact
 e3fa0ee71f071bb8cff667d50ee1c0da6827a7c9 (core source notification + B662).
No AGENTS.md in this tree. Source changes only owned gateway.rs and gateway tests.
No production tail fix or guessed core API is present; do not merge as a repair.

Real fixture: initialize canonical document and artifact stores, register original
synthetic UTF8 Text, issue real current document/project grants, run StoreEvidence
process/find_literal/open/resolve_local_evidence_trusted, bind its actual proof.target
through issue_local_evidence_binding_trusted and save a real manual form draft.
No hand-built source record, fake anchor, validation/engine receipt or external call.

Gateway initially could not decode existing DocumentFormat::Text.01 normal Cargo
attempt is an upstream COMPILE failure, NOT behavioral RED; worker's source notification
hook cannot find real invalidate_local_evidence_sources_in_transaction. We preserved
it and used actual library + rustc to run the unchanged integration test source.
02 actually demonstrates Text codec StorageCorrupt. One owned metadata decode arm
fixes existing Text identity (no grant/engine/permission change);03 passes.

04 actual two regression REDs (exit101): AFTER UPDATE OF receipt_json, WHEN the
real journal transitions committed, DELETE its real notification or set pending=0.
Both commit_copy return Ok(Committed), publish source head2/ref/revision and a success
receipt despite notification absence/premature ack. This is the specific gap after
core clone's internal source/blob/head verification but before gateway grant-only tail.
05 positive control passes: normal real-source COPY queues exactly1 pendinggeneration1,
invalidates real source+binding, preserves manual values.06 full gateway direct run:
21pass/2FAIL (23tests), including all previous19; counts overlap, do not add runs.

Reproduce with existing toolchain1.90/cache/SQLite linker alias env from earlier reports:
`python3 docs/tasks/document-source-tail-20261022/verify-gateway-direct.py /workspace/document-source-tail-20261022 receipt_tail_cannot_`
Driver only cargo-builds the REAL library then rustc--test links the actual gateway
integration test and runs it; it changes no core/lib/worker source and has no fake
executor. It does not close normal Cargo/worker or strictClippy gates. Raw01-06 are
untrimmed; driver-created build JSON/compile/test evidence paths appear in each log.

Fresh independent reviewer personally reproduced both actual REDs and positive1/1,
confirmed whole real evidence chain and actual Cargo compile blocker. Raw outputs,
source hashes and statuses in evidence/independent-source-tail-red/. Notification
P2 remains open; this result is not dispatch-as-completion or a fixed/green claim.

See POSTCONDITION-REQUEST.md for precise core-owned capture+read-only verifier
contract. Parent is coordinating the owner; only after fixed interface arrives will
we wire it AFTER last receipt write, BEFORE final grant and COMMIT, preserving all
original transaction boundaries. No mock postconditions, new permissive identity,
repair/re-invalidation or guessed API. Worker assembly fix also belongs to owners.

Originalcandidate721077297ba77471ede80b653274cec4a8224655 and minimalclippyec41e16b67cde7a9949ffe9e6e732b6cd43f8f44 remain untouched. No main/develop edit/merge,
force/delete/deploy, model/search, user-file, payment/credential/permission change or
retry of the historical unknown requests. Only Leader B integrates develop.
