# Unicode admission and native owner recovery

The fifth API26 run exposed a persistent owner lock after the malformed UTF16
codec test. UniFFI 0.32.2 clones the object handle before lowering String arguments;
its strict UTF8 encoder can throw before native code consumes that clone. This
retains the Rust owner even after closing the original Kotlin object. The generated
bridge has not been manually patched.

`WireText.kt` now rejects unpaired surrogates in the client and private Service
before any native object call. Both raw JSON and recursively parsed strings/keys
are checked: ASCII JSON escapes can otherwise carry an invalid surrogate past a
raw-string-only guard. Valid pairs continue unchanged to Rust normalization.

The actual `ContractCodecProductTest` requires a changed native owner epoch in
the **same Service process**, after malformed input rejection and closing the
client. Reconnecting to the same old owner or killing the process cannot satisfy
the test. This case passed in the seventh API26 run on emulator-5556, together with
the valid Unicode codec test, saturated-request close test and six supplier/research
tests (9/10 total passed). The remaining recovery assertion queried only the first
10 suppliers despite retained test data; it is being corrected to enumerate actual
pages, with the original receipt/epoch/unique-record requirements retained.

Evidence: `/private/tmp/muyon-product-api26-fifth.log`,
`/private/tmp/muyon-product-api26-seventh.log`,
`/private/tmp/muyon-product-apk-build.log` (build/lint success).
The sixth run also used two incorrect test class selectors; that failed run is not
accepted as a passing suite. These are provisional candidate results, not the
final source-sealed suite or all 36 acceptance scenarios.
