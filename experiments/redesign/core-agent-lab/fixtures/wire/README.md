# Independent offline wire fixtures

Authored from SPEC/C0 WIRE-CONTRACT at9b569f9 before reading new Rust
implementation. Raw `.sse` files are provider inputs, not converted TSV events
or expected actual-result tables. `scenarios/cases.json` contains checker
expectations only; the core/helper never reads it. Per-scenario config contains
only trusted input response/exit/hold controls.

The stdio helper implements the frozen `--fixture-dir/--turn/--capture-dir` ABI.
It saves exact stdin bytes as `request-N.json` before emitting anything. Request2
answer text is JSON derived from the received role=tool content's actual value
and receipt; it does not contain a preselected expected answer or business
receipt. The independent checker compares captures against physical effects.db.
Exclusive capture prevents repeated admission from overwriting old evidence.
No socket, model SDK, credentials, HTTP or network client exists in this helper.

Inputs cover fragmented arguments, UTF8/escaped Unicode, CRLF/comments/multiline
data, usage-only chunks, missing/wrong/duplicate/trailing terminals, incomplete
framing, invalid/duplicate/extra args, unknown/legacy tools, mixed/multiple calls,
metadata conflicts, strict JSON/UTF8, depth and argument/line/event/response caps.
Some deliberately invalid fixtures exceed a protocol bound; they are not accepted
configuration or production examples.

Hold controls exercise silent service, stdout EOF with a live child, or a child
that never reads request stdin. They are trusted fixture faults, not provider
message privileges. They use signal waiting, not sleep-based race ordering.
Capture PID files support handled cancel/error/timeout cleanup checks. External
SIGKILL of Rust cannot run Drop: the harness must explicitly kill/reap any
surviving fixture child and label that cleanup, without claiming autonomous
parent-death supervision. All raw runtime logs/captures remain outside Git.
