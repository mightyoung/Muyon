# RD-P08 Android presentation experiment

Private synthetic D01.1 source slice. M03 remains **blocked_contract**. There is no production wire, formal Auto/FullAllow grant, Android HTTP/JNI adapter or installed Android/Compose dependency here. The page consumes the [shared experimental boundary](../CONTRACT.md) and [host projection](../host/PROJECTION.md).

`SupplierScreenModel.kt` is stdlib-only typed projection/navigation/action code. DTO field names correspond directly to the experimental host projection and original P07 receipt; there is no second JSON parser. Revisions stay decimal strings. `OriginalReceipt` and its complete original binding are host-supplied data, never generated or verified here. The host/P07 alone owns normalization, validation, CAS, complete binding, durable sessions and original receipt verification. A dishonest adapter is outside this UI trust boundary.

`SupplierPage.kt` is a source-only Compose phone list → detail → full editor. Stable supplier IDs distinguish equal names. Current row and historical original receipt are separate, with current/old/raw/preview labels. Buttons call the injected model port. It includes discard/keep confirmation for unresolved pre-dispatch buffers, a system-back handler, visible labels, heading/status semantics, 48dp minimum action height, and a scrolling layout with system/IME padding. These are source design provisions, not measured accessibility acceptance. Unknown/saving cannot cancel, change raw or create a new intent. A binding conflict cannot be dismissed as a confirmed CAS rejection. Only host `Revision` conflict permits explicit discard and fresh edit.

The model allows local typing while its draft callback is in flight, serializes latest exact raw to the host, and disables save until host raw and local raw agree and the host is prepared. It locks typing during preview/save callbacks. Double pending clicks are suppressed. Session-mismatched/duplicate callbacks cannot establish success. An uncertain save transport reply keeps the original session and permits lookup, never save replay. A saved label requires a host-supplied original receipt. There is no independent business validation in this presentation layer.

A future native composition must supply `SupplierActionPort`, retain the original opaque `session`, obtain current `csrf` on GET after restart, and implement exact loopback metadata/body validation through the trusted host. `restoreOriginalSession` selects an advertised original session then GETs its state; it is not a new host action and must not silently create/rekey a missing session. Deliver callbacks on the UI thread. Failures return `PortReply.Unavailable`; do not retry writes. Construct `SupplierScreenModel(initialHostProjection, port)` and pass it to `SupplierPage(model)`. No transport implementation is claimed. Local input not yet acknowledged by the host exists only in this model; app-process recreation preservation is **NOT_RUN**. A missing current read stays unavailable, never reconstructed from receipt.

Run the complete new pure-JVM projection/action suite with existing tools only:

```bash
./experiments/redesign/device-deferred/operable-supplier-flow/android/run-jvm-tests.sh
```

Tool paths may be explicitly overridden by `RD_P08_KOTLINC` / `RD_P08_JAVA`; defaults reuse the installed Kotlin 2.2.20 and JDK 17. The runner compiles **only** `SupplierScreenModel.kt` and `ProjectionTest.kt`, writing its jar into a new private `/tmp` directory. It leaves the artifact for review. No dependencies are installed, no old P05/P06/P07 suites rerun, and no product/build/schema/CI files change.

Evidence: synthetic typed projections and recording callbacks test JVM presentation behavior, including exact raw lone-surrogate preservation. They do **not** execute the host, Rust, SQLite, an Android runtime, Compose or a device. Compose compile/render/launch, Android transport/native load, rotation, TalkBack, IME interaction, 200% fonts and device tests are **NOT_RUN**. Independent desktop/mobile browser evidence belongs to the desktop/host reports and cannot establish Android native behavior.
