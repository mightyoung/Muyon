# Independent host expectations frozen before implementation

Contract: `HOST-CONTRACT.md` at `2cd3ad0`; source fixtures read at
`aa15e8b2cb5b24b1f973b282f9181a9b01d13182`. No new DUT implementation
or output was consulted to define these expectations.

The positive test uses `MuyonHost.open`, `activateInquiry`, the ordinary supplier
store and `resolveAssistantScope`, following `test/business_tools_test.dart`.
Supplier name is `PRIVATE_HOST_SUPPLIER_7e84`; notes are
`PRIVATE_HOST_NOTES_c391`. The supplier ID and reference metadata come from that
temporary store; no business identifier or metadata is invented. Secret is the
synthetic `sk-HOST_AUTH_CANARY_460a`, supplied only through the mocked platform
SecretStore method channel. Native model call ID is `model-pair-41`.

First model response proposes encoded native tool `inquiry__object` with exactly
`{type:supplier,id:<created ID>}`. Second response depends on observing the exact
expected projection in the second captured gateway request. The expected
projection is built independently from the selected actual ObjectRef, with keys
`found`, `objectRefs`, and the five reference keys specified by the contract.
Never copy a DUT projection or whole result JSON into an expected value.

The task must finish successfully before waiting for protocol markers. Against
the compiling default-off stub this is an ordinary assertion failure, never a
missing-frame timeout counted as RED. Initial RED CI may select only the exact
positive test name. The full required suite runs before GREEN.

Positive evidence requires two actual gateway ledger rows, one original registry
receipt containing the private record, a distinct host/core invocation identity,
the original native call ID paired with the second request's tool message, no
tools on turn two, and a real compiled Rust process. Python forwards bytes
unchanged and records them in a temporary directory; it does not replace the
positive child or construct its replies.

Additional independent cases cover disabled legacy, invalid config/no fallback,
unsupported capability, one active task, scope denial/no invocation, effective
model confirmation/denial, forged arguments and incomplete turns, second tool
turn rejection, cancel while model pending, close/reap, receipt retention on
cancel, restart continuations, codec/correlation failures and metadata bounds.
Only negative protocol tests may use an artificial child. Synchronization uses
Completers or explicit process file barriers; no timing sleeps define success.

Missing executable is an error. Compiler errors and timeouts do not count as
semantic RED or killed inverse controls. Raw logs remain outside Git. Actual
RED/GREEN and inverse results are filled only from terminal CI output.
