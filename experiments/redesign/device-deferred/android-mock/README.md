# RD-P04 — Android supplier screen and provisional mock seam

This isolated Kotlin laboratory implements the D01.1 synthetic supplier-name UI
state. It uses no real database, model, network endpoint, Android runner or native
library. `RustCorePort` is a replaceable in-process adapter interface, **not** the
M03 product DTO, wire format or selected transport. Its intent/plan strings are
mock identifiers, not durable production identifiers.

## Run the complete JVM suite

```sh
experiments/redesign/device-deferred/android-mock/run-tests.sh
```

Defaults reuse the existing Kotlin 2.2.20 / Temurin JDK 17 toolchain. Override
`RD_P04_KOTLINC`, `RD_P04_JAVA_HOME`, `RD_P04_OUTPUT` for existing local tools.
The output jar stays in `/tmp/rd-p04-output`; no dependencies are installed.
`SupplierScreen.kt` is intentionally excluded from that stdlib-only JVM command.
It requires a future host with Compose Material3 dependencies. Compose compile,
render, TalkBack, font scaling, rotation, keyboard and Android actual load are
**NOT_RUN**, not inferred from presenter tests.

## Implemented and tested behavior

- Loading/list/detail/edit are immutable state projections keyed by supplier ID;
  same-name rows remain distinct. Back navigation keeps raw draft and intent.
- Every UTF-16 code unit, including whitespace, combining sequences, XML-invalid
  control characters and lone surrogate, reaches the port unchanged. Only the
  future Rust kernel may perform XML check → trim → NFC → length validation.
- Preview returns a port decision: ALLOW directly commits once, CONFIRM stages a
  plan for explicit confirmation, HARD_DENY refuses. ALLOW has no additional
  risk/new-endpoint question. The mock does not implement real policy evaluation.
- Dispatch is distinct from effect: no effect receipt means no saved state.
  Unknown preserves its intent/draft and never resubmits automatically. Conflict
  keeps the raw draft and projects the current saved value supplied by the port.
- Display generation, same-domain snapshot watermark, object revision and intent
  identity are separate. Cross-domain snapshots and older display callbacks are
  rejected. Late matched receipts are retained by their original intent even
  when another supplier is displayed. They never switch that display.
- Matching requires the exact dispatched command, original supplier and nonblank
  receipt. A final effect cannot be downgraded by a late timeout/conflict. Explicit
  editing after a shown effect creates a fresh intent with the observed revision.

## Trust and unresolved work

Only a trustworthy adapter may be passed as `RustCorePort`: the adapter must check
scope, purpose, permission, source and effect provenance. This sample does not
make arbitrary DTOs authoritative or implement cryptographic verification.
`MockRustCorePort` publicly emits synthetic outcomes for local tests only.
Callbacks and UI actions must be serialized on the host UI thread; no concurrent
presenter guarantee is claimed.

Drafts, commands and receipt ledger are **in-memory**. Durable crash recovery,
read revocation clearing, write revocation, read-only reconciliation for unknown,
explicit conflict resolution, new-stream resync and projection persistence remain
required. Equal domain/watermark snapshots rely on the future adapter's atomic
snapshot contract. Receipt state does not forge an event cursor or advance the
snapshot watermark. Reopening a supplier uses the last accepted snapshot; it
requires a newer authoritative snapshot to refresh the list after a late effect.
No real native Rust adapter is wired, and no product authorization rules/schema
have been frozen. M03 remains **blocked_contract**. Devices are deferred for
continued reversible development, but release and device acceptance gates remain.
