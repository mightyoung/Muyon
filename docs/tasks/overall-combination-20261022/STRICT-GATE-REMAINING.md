# Strict gate reached remaining FFI/storage targets

Fixed code67fd14c4259acf9275d7a20c5643bcb2f2671d16 imports gateway-test owner
2e2cfcdec28c5ecdf4ebc45523fc0885d4b0a9da over0e325011. Exactly5drop(g)
lines removed. Actual drop(s), drop(db), reopen order and assertions unchanged.
The complete fixed source (all owned pins + unique exports + generated bridge)
was independently reviewed read-only; no new composition finding. No host save
permission, second authority/driver or candidate/schema2 change.

Actual full product workspace PASS435 executions/0FAIL/0ignored,26groups,
FFI14/core421. Counts include duplicated source-module harness coverage; do not
sum targeted/earlier runs. Exact command and raw log under evidence/.

Actual strict workspace/all-target Clippy Rust1.93.1 FAIL101. All prior gateway
5drop_non_drop diagnostics and original50 diagnostics are gone. New targets emit:

| Source owner / accepted pin | Exact location relative to crates | Diagnostic |
|---|---|---|
|Provider31602082 via current8b2d7783|muyon-android-ffi/src/lib.rs:181:5|too_many_arguments: local_draft_save10/7|
|Coreaec085fa|muyon-core/tests/document_storage.rs:685:24|manual_repeat_n: repeat(' ').take(262144-payload.len())|

The FFI error repeats for lib-test; it is not a separate issue. No lint suppression
was added. Provider owner must resolve the public boundary consistently with host
and generated bindings; integrator does not independently redesign that owned
API or silently borrow a next-batch method. Core owner can use repeat_n at its
existing test expression without weakening the bounded-input test.

Original source authors retain their files. Parent forwards fixed minimal SHAs;
then rerun full strict gate, affected behavior and fixed-source review as needed.
No global allow or fake Drop implementation. Later target status cannot be inferred
until the full command actually exits0.

## Next combination is intentionally not started yet

User's ordering requires current strict gate closure before next batch. Accepted
next candidate dependency corefaeef3aec3a9407d7c15490dcdb33866413e7453 + bridge
721077297ba77471ede80b653274cec4a8224655/source57c326a5ba790ccca44e25a0a7ebbe9cf9604eee
remains outside current435. Worker fix evidencef076e068e65b59b1b0aff0efefd9fa540f176e86
is separate, including repeated48/core240 and prior failures. Never claim publish.

Next provider098d9aca214e6642c1b3ffde64921ebedbae335d was offered pending parent
review, with fifth local_draft_prepare_save and stateful lookup reconciliation.
It is not imported or covered by current4-method FFI14/435. Future actual tests and
five-method generation are required; lookup must not be called a pure read.
No verified=false enablement or host can_save release from these queued inputs.

Broader host/evidence/canonical group gateway wiring, absent Android toolchain,
real engine/model/fee parameters and paid/device acceptance remain unchanged.
No PR, main/develop merge, deployment, credential action or old403/I04 retry.
