# Third-party provenance

PaddleOCR SDK sources and recognition YAML configurations: Copyright PaddlePaddle
Authors; Apache-2.0, immutable source/model revisions in the lock files.
The desktop DB postprocessor credits WenmuZhou/DBNet.pytorch in its retained header;
its source and narrowly documented NumPy adaptation are fixed in reference-sources.json.
The extracted perspective-crop helper is unchanged from PaddleOCR at the same commit.

ONNX Runtime1.21.1: Microsoft, MIT (full license retained). Current Android runtime
uses official `org.opencv:opencv:4.12.0` from Maven Central, Apache-2.0 (full OpenCV
license retained). QuickBird OpenCV4.5.3 remains historical audit evidence only.
OpenPnP OpenCV4.9.0-0 is a desktop JNI test dependency, Apache-2.0; it is not
packaged into Android. Byte Buddy/agent1.15.11 are test instrumentation only,
Apache-2.0.
Kotlin/coroutines/serialization: JetBrains, Apache-2.0. JUnit4: Eclipse Public
License1.0. These are build/runtime dependencies, no binaries redistributed here.
Gradle and external Python tools have their own distribution licenses; this module
does not redistribute them. Actual App distribution must retain dependency notices
and libc++/NDK notices for the final chosen binaries; this is not a release SBOM.

Synthetic test strings, programmatically generated image pixels and JSON fixtures
contain no user documents. No font binary is redistributed.
