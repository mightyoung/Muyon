# RD-P06 isolated durable recovery lab

Status: provisional synthetic experiment; implementation and independent verification pending. This is not the M03 product schema, a production database, or an exactly-once contract.

Baseline: `676331048611aa1fb0f226ec300f6bac633e98a0`. Inputs: [D03a](../../../../docs/contracts/redesign-v1.3.2/recovery-minimal-contract.md), [D03a experiment](../../../../docs/tasks/REDESIGN-D03A-EXPERIMENT-20261014.md), and the two v1.3.2 design books. Earlier in-memory RD-P01/P02/P05 evidence does not prove durability.

## Minimal experiment

Use existing offline Rust dependencies and Linux filesystem APIs in a new private synthetic temporary directory. No production paths, user data, models, devices, new dependency installation or licence acceptance. The trusted test harness selects the directory and executable; this CLI is not a renderer API or a grant.

An intent binds the complete synthetic ordering domain, operation, target and arguments. Exact duplicate requests preserve the original result and produce no additional effect after a process restart. The same intent with a different binding conflicts; changing the process epoch does not create a new intent.

This lab uses one fixed ordering domain. Wrong-domain inputs fail closed; this does not implement stream rotation or backup restore. Stream changes must never re-mint an existing business intent. A snapshot at an existing watermark with different content conflicts rather than replacing the committed pair.

Persist the binding and pending boundary before dispatch. The synthetic effect must modify a separate physical effect store, independently observed by tests. A pending record can mean that dispatch happened: missing receipt, missing effect evidence or an interrupted response cannot prove zero effects. Recovery and lookup never automatically redispatch. Preserve unknown until the trusted local synthetic effect source supplies matching evidence; lookup cannot manufacture a receipt from a client claim.

Store the projection content and complete cursor domain/watermark as one recoverable committed pair. Receipt evidence and the visible projection are independent: stale epoch data cannot replace current projection, while verified old-effect evidence remains available. A stale snapshot or history gap cannot erase a receipt. This lab does not implement retention controls, chat persistence, memory/tombstone restore, backup migration, formal authority validation or trusted user instruction acknowledgement.

The directory has one writer at a time. Contention must fail closed, and process death must release writer ownership without unsafe stale-lock deletion. Invalid/truncated persisted data and write failures cannot trigger effects. Storage mechanics must describe their Linux and filesystem assumptions; process-exit tests do not prove power-loss survival, cross-device atomicity or external-provider exactly-once.

## Verification gate

First collect real assertion RED from subprocess tests using actual temporary directories and exits at persistence boundaries. Then implement the minimal store and collect GREEN. Required fault coverage includes before/after pending, after effect but before receipt, receipt persistence before lost response, and before/after projection pair commit. Reopen with a new OS process and inspect physical state, stable bindings and effect counts.

Run inverse mutations for pending-before-effect ordering, unknown replay, and receipt/projection isolation or atomic pair recovery; each must fail a behavior assertion. Restore source bytes, rerun GREEN, and retain raw logs outside Git. Report exact source SHA, command exits, test counts, fault boundaries and limitations.

Before any intake: immutable non-author review and fresh candidate CI on the latest develop combination. The original RD-P05 SQLite CI RED remains unexplained historical evidence; no rerun or inferred root-cause fix is authorized by this lab.

Existing CI does not execute the new Rust lab. Record exact-source local subprocess/fault/mutation results separately from candidate CI's existing Flutter regression checks; a successful CI run cannot substitute for this lab's verification.
