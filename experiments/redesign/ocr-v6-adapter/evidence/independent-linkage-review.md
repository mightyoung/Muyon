# Independent follow-up — native linkage containment

Reviewed fixed candidate `d1c8096d22e2281641cccc7f8e5e8cd5490f1a14`
on 2026-10-18. `git rev-parse HEAD` and `git show --stat --oneline` confirmed
that exact HEAD before review. Scope: incremental changes since `8684e1ca`,
especially the second finding in `independent-review.md`. Only this follow-up
report was added; original review/logs, runtime, tests and host were not edited.
The pre-existing untracked `evidence/verification.json` was left untouched.

**Finding 2 resolved for the independent adapter contract.**
`kotlin/src/main/kotlin/com/mightyoung/muyon/ocr/OcrExecutor.kt:65-68` preserves
CancellationException and OcrFailure, retains the existing Exception mapping and
adds a specific LinkageError mapping to a new `OcrFailure(INFERENCE_FAILED)`.
This covers UnsatisfiedLinkError and ExceptionInInitializerError without catching
unrelated fatal VirtualMachineError subclasses. No loader message/cause is copied
into the returned exception. The existing non-cancellable finally at line 62
still closes an already-created runtime when inference throws a linkage error.

`kotlin/src/test/kotlin/com/mightyoung/muyon/ocr/AdapterTest.kt:82-89`
injects UnsatisfiedLinkError during factory creation and
ExceptionInInitializerError during inference, verifies the controlled result and
one close for the created runtime. Its shared assertion at line 26 verifies that
message equals the stable enum name and cause is null. Existing coroutine
cancellation/release and ordinary inference failure tests continue to pass.
`evidence/linkage-red.log:21-23` records the targeted prior failure;
`evidence/linkage-green.log:21` records it passing after implementation.

Independent verification command, from `/workspace/muyon-ocr-v6`:

```sh
JAVA_HOME=/workspace/toolchain/jdk17 /workspace/toolchain/gradle-8.13/bin/gradle --no-daemon -g /workspace/toolchain/gradle-home -p experiments/redesign/ocr-v6-adapter test --rerun-tasks
```

Result: **15 tests passed**, BUILD SUCCESSFUL in 16s, 5 tasks executed. This
includes compiling the Android/vendor signature sources and running JVM tests;
it does not execute Android native libraries or prove actual loader recovery on
a device. Rust/Python were not rerun for this Kotlin-only fix; their prior fixed
candidate review evidence remains in the original report.

No new blocking defect was found in this increment. The independent source and
contract slice can be sealed and handed off. **Finding 1 remains open and blocks
formal App integration:** inherited QuadTextCrop/DetPreprocessor exceptions lack
deterministic temporary-Mat cleanup. README and the task note now explicitly
retain that blocker. Existing min26/product-min24 packaging, OpenCV 16KiB,
Service/source/store/PDF and real-device gates remain unchanged. This follow-up
does not authorize or claim production integration, merge, deployment, native
error/OOM cleanup, or device performance validation.
