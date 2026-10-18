# Private supplier read contract oracle (proposal)

This is a Python standard-library **contract oracle**, not production Rust/Kotlin,
not a fake chat UI, and not evidence of a real Service/Binder/tool/model loop.
It contains no networking, subprocess execution, SQL, grants, credential access,
or provider calls. No existing runtime, UI, AIDL, or Gradle files are modified.

## Execute

From repository root:

```sh
python3 -B -m unittest discover -s experiments/redesign/frontend-service-loop-lab -v
```

`evidence/RED.log` records 13 tests / 10 assertion failures against the initial
fail-closed scaffold (3 rejection tests already passed). `evidence/GREEN.log`
records 13 tests / 0 failures against the implementation. This is test-first
contract behavior evidence only. Rust/Kotlin/Android project suites are NOT_RUN:
`rustc`, `cargo`, `kotlinc`, `adb`, and `flutter` are absent in this environment.
No toolchain was downloaded. Existing source facts were read from the fixed
NEXT-REAL-LOOP handoff, AgentServiceContract.kt, IAgentRuntime.aidl, and
service_types.rs; this proposal does not widen those ABIs.

## Proposed bounded shapes

Submission has exactly `protocol=1`, `epoch`, `lease`, `request_id`, `text`, and
`selected`. The selected object has exactly `module_id='inquiry'`,
`type='supplier'`, `key`, and `revision`. The text is nonempty UTF-8 <=4096 bytes;
identifiers are ASCII letters/digits/underscore/hyphen, 1..128 bytes. These
limits/identifier grammar are proposed, not a guarantee that existing supplier
keys/revisions fit them. Unknown fields at either level are rejected, including
path/SQL/grant/credentials/endpoint/approved. Chat text is data, never executed;
this oracle is not a natural-language injection filter or an authority resolver.

Events have exactly `epoch`, `request_id`, `run_id`, `cursor`, `kind`, `payload`.
`epoch` is the **admitted Service epoch**, retained across reconnection. Cursor is
an integer (not bool), contiguous from 1, at most 1024 per run. The four payloads:

- `answer_delta`: `text` <=4096 UTF-8 bytes, total answer <=32768 bytes.
- `receipt`: original durable `opaque_id` and `outcome` of `recorded_success` or
  `recorded_failure`. It is never generated from the selected object or cursor.
- `supplier_projection`: `key`, `revision`, `name` <=512 UTF-8 bytes, `receipt_id`.
  It requires the exact selected object/revision and a matching successful receipt.
- `terminal`: `outcome` in completed/cancelled/failed/budget_exhausted/unknown.
  Completion requires an observed durable-success receipt.

Identical cursor replay is idempotent; changed replay conflicts; gaps and identity
mismatch do not mutate state. Termination is monotonic. Invalid events are rejected
atomically. A conflicting receipt cannot overwrite historical receipt identity.
Projection invalidation clears current display data and preserves historical receipt.
A new projection after authority changes requires the future host authority gate:
this oracle cannot establish that permission from event data alone.

Binder loss marks a nonterminal run UNKNOWN and invalidates projection. It never
creates a failure or successful receipt. `reconnect` only models a verified new
connection `(current epoch, new lease)`; it preserves admitted epoch. Recovery uses
that new connection with `('lookup', request_id, run_id, cursor)` and never submits.
The caller must authenticate observations/tickets and reject stale callback delivery.
An admitted state always has `can_submit=False`, including after cancellation or
UNKNOWN. Cancel returns requested, never invents a terminal observation.

## Deliberately pending production design

Event source authenticity, per-connection observation tickets, reauthorization on
projection display/recovery, durable event storage, stream polling/page limits,
terminal failure reason codes, original receipt ID wire encoding, source namespace,
and the match between supplier revision grammar and schema12 remain integration
owner decisions. The bounded cursor overflow is a fail-closed invalid event here;
a production protocol must negotiate or reject oversized streams before execution.
No durable admission/replay policy or cancellation RPC implementation is supplied.

Real Android private Service/AIDL/native execution, isolated Rust registered read,
Android schema12 adapter, authoritative scope bridge, and approved model provider
are **NOT_RUN / not implemented by this oracle**. The I04 legacy HTTP operation
remains denied and is neither retried nor represented here. Main/develop, dependent
merges, network calls, deployment, and credentials are untouched.
