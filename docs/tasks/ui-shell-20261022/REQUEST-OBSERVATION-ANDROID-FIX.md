# Android JSONObject request-observation compatibility fix

Reported actual Android CI source a62c88ce2b46d4d3a7a1f78477f08384a671a84d:
https://github.com/mightyoung/Muyon/actions/runs/39751747058
The parent supplied the actual Kotlin error: RequestCandidates.kt:24:49 unresolved
reference similar. This supersedes any implication that local JVM JSON-java passing
proved Android compatibility. Local full Gradle still cannot resolve AGP8.11.1;
the CI failure demonstrates a separate real production API defect.

## Minimal fix and schema boundary

Only RequestCandidates.kt and its existing RequestCandidateChecks.kt are changed.
JSONObject.similar is replaced with keys/has/opt/length comparison of the entire
finite schema1 flat observation. No rendered ReadOnlySnapshot comparison, string
serialization comparison, removed validation or application dependency replacement.
Every key, including cancelled, attempted and current_business_state, participates.
Object key order is irrelevant. Absent differs from explicit JSONObject.NULL;
String/Boolean/Int/Long/Double values must match both representation type and value.
Scalar types cannot coerce into each other. Unknown nested objects, arrays and
non-JSON objects fail closed, even when they match; this is intentionally the flat
schema1 contract, not a general JSON equality library. More than64 facts fail closed.

## Actual offline evidence

Real dependency used only as an external test classpath, not app dependency:
Maven Central com.vaadin.external.google:android-json:0.0.20131108.vaadin1
https://repo.maven.apache.org/maven2/com/vaadin/external/google/android-json/0.0.20131108.vaadin1/android-json-0.0.20131108.vaadin1.jar
SHA256 dfb7bae2f404cfe0b72b4d23944698cb716b7665171812a0a4d0f5926c0fac79.
This actual Android org.json fork has no similar; it is not a homemade Android stub
and is not proof of target API36 runtime acceptance. Its raw keys iterator also
exposed a String typing issue on the first attempted fix, corrected with checked
String casts. Original platform RED and first-fix RED remain archived separately.

Old immutable c0c2dc994df099c36c83813adf8410dac999d943 RequestCandidates.kt
compiled with actual ReadOnlySnapshot.kt and this jar: exit1, exactly unresolved
similar (request-observation-original-platform-red.log). Test-first new helper
missing-signature compile RED: request-observation-api-red.log. First fix raw
iterator failure: request-observation-android-json-first-red.log.

Final command from repository root:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/android-json-0.0.20131108.vaadin1.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

All3 runners PASS exit0: actual Host/controller, candidates and cold shell, including
added positive reordered-object and negative missing/null/type/full-hidden-fact
checks. request-observation-android-json-green.log. JSON-java20250517 also all3 PASS
(request-observation-json-java-green.log). Independent rerun/review recorded in
REQUEST-OBSERVATION-REVIEW.md and request-observation-independent.log.

No real transport/native/model request. No Runtime/Service/bindings/reader changes,
no external JSON library added to APK, and unrelated reader consent work is excluded
from this commit. Scope is compatibility plus retained duplicate-observation guard.

## Remaining validation

B must combine this exact isolated commit into its feature combination and run the
existing narrow Android CI to terminal outcome. This worker has not triggered CI
or claimed Android build/APK/device PASS. Local Gradle AGP8.11.1 resolution and prior
SDK read-only filesystem blockers remain, with reader-consent-android.log and prior
reader-surface-android.log retained in their separate batches. They are toolchain
failures, not approval denials. main/develop unchanged by this worker.
