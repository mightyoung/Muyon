# Temporary Mat ownership adaptation

Upstream: PaddlePaddle/PaddleOCR `dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf`.
The Apache-2.0 source notices remain unchanged. The adaptation changes ownership
cleanup in QuadTextCrop, DetPreprocessor and ImageUtils; numeric operations and
parameters remain upstream defaults.

## Reproduction

Desktop JNI: `org.openpnp:opencv:4.9.0-0`; test-only ByteBuddy 1.15.11 instruments
actual `Mat` constructors and `release()` calls. These are real native Mats and
native OpenCV operations, not Mat mocks. Every observed temporary must have an
explicit release call and report `empty()` before cleanup by the test harness.
Only the returned successful crop may remain live; the caller releases it.
The source Mat is created outside the observation window and remains borrowed.

`mat-red.log` and `mat-red.xml` are the unmodified-source run: 21 total JVM tests,
5 failures, all expected ownership assertions. Crop with an empty source produces
a real native CvException and retains 2/5 temporaries; one-channel detection
produces a real index exception and retains 3/4; RGB with rejected resize arguments
retains 1/1; empty-source resize produces a real CvException and retains 1/1.
Injected cancellation at warpPerspective initially retains 2/5.
The 20-round successful path already passed before the fix.

Cancellation is injected by test-only method advice before cvtColor, convertTo,
split, warpPerspective and rotate, preserving actual allocations made earlier in
the pipeline. It exercises CancellationException unwinding; it does not claim
that synchronous native OpenCV itself polls coroutine cancellation.

The normal path checks BGR/RGB normalization, crop/vertical rotation dimensions,
borrowed source ownership and successful crop ownership across 20 repetitions.
A separate extraction-time observation checks that the RGB, resized and floating
intermediate images have already been released while the three split channels
are read. `mat-lifetime-red.log` tests the cleanup-only variant before restoring
the original early-release lifetime.

The final `mat-green.log` / `mat-green.xml` records the complete JVM suite.
`mat-setup-*.log` preserves setup/interruption/stale dependency-lock failures and
is separate from the product RED checkpoint.

These checks prove explicit JNI release ownership on the desktop implementation.
They do not measure native headers, process RSS, peak memory, Android ART behavior,
16 KiB loading, or device cancellation latency; those still require device tests.
