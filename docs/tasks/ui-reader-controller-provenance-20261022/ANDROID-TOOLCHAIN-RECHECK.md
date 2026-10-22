# Actual Android compilation after authorized tooling restoration

Exact candidate tested: `dde185602f3d0f54ec4a3fe9ea635872a971c9e6` in `/workspace/Muyon-reader-provenance-20261022`. No production/source/configuration changes before/during verification; this commit adds evidence only. Original NOT_RUN logs remain, superseded only for this compilation check.

Result: **FAIL (exit 1), compileDebugKotlin actually executed; RequestCandidates.kt:24:49 unresolved reference similar.**

## Official task-local tools

Project pins: Gradle8.13, AGP8.11.1, Kotlin2.2.20, compileSDK36, BuildTools35.0.0, JVM target17. Existing PATH/workspace caches were checked first. System Java21 was runtime-only, lacking JAVA_COMPILER. Tools installed only under `/workspace/host-projection-tools/android-build`, no sudo, credentials, payment or expanded permission.

- Official Gradle https://downloads.gradle.org/distributions/gradle-8.13-bin.zip, SHA25620f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78, verified against official .sha256.
- Official SDK https://dl.google.com/android/repository/platform-36_r02.zip (API36 revision2, SHA1 2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576) and https://dl.google.com/android/repository/build-tools_r35_linux.zip (35.0.0, SHA1 2cfaa0bbb2336e9ec18ed3ecea84fa2e2af607bc). Both matched https://dl.google.com/android/repository/repository2-3.xml. Actual source.properties preserved package identities. No replacement Android classes/stubs.
- Official command-line tools23.0: commandlinetools-linux-16111833_latest.zip, metadata SHA1 e025545c62a8e64c7559119566a569fb1dec5f60. Its sdkmanager now delegates to Android CLI and installed official platform-tools37.0.1. No `yes` or all-licenses acceptance used. Only existing android-sdk-license acceptance file is present. No further CLI/metrics command is needed for compilation.
- Official Eclipse Temurin17.0.17+10 complete JDK (JVM target17 required, patch chosen explicitly; project does not pin patch), metadata https://api.adoptium.net/v3/assets/version/17.0.17%2B10, release https://github.com/adoptium/temurin17-binaries/releases/tag/jdk-17.0.17%2B10, archive SHA256992f96e7995075ac7636bb1a8de52b0c61d71ed3137fafc979ab96b4ab78dd75, verified. javac17.0.17 exists and is used.

## SDK agreement version record

Authorized Google Android SDK agreement only. Required packages reference `android-sdk-license`. Metadata embedded text is dated January16,2019; live official https://developer.android.com/studio/terms displays April28,2026. Both identify the Android Software Development Kit License Agreement with Google, not a new third-party contract. Word comparison records current company LLC/location, HTTPS links, acceptance wording, privacy URL and added section6.3 anonymized/aggregated data sharing with Google partners, shall/will wording and date changes. User explicitly accepted the disclosed official SDK agreement before this installation. We registered only the package-referenced agreement, not any other SDK/system-image/third-party agreements. Metadata text SHA256 `1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16`; live extracted agreement SHA256 `6421dc3269706b2f0119cf8e2a5248a4324e22cc7a0ecdf10dd1ee51f0d03285`. Originals retained in task-local tooling directory.

## Network and filesystem handling

Initial unconfigured-proxy commands were terminated after no-progress and confirmed exit143; logs retained. Existing HTTPS_PROXY was mapped into task-local Gradle properties with no credential and15s connection/read timeouts. No proxy server, VPN, system network or security setting changed. Default home write failed; existing Android/Gradle user-home environment options moved only caches into the writable task directory. Initial full JDK trust failed PKIX; final run used the SAME existing system trust store used by preinstalled Java21 (`/etc/ssl/certs/java/cacerts`, SHA256 f000296c30a423c8a150a1381661d4a3fb230b75718f315b88bed8d0395d1f16), read-only, via this process's JAVA_TOOL_OPTIONS. No new certificates, disabled TLS checks, altered system trust, third-party mirror or retries of uncertain business requests.

## Exact final command

Run from `/workspace/Muyon-reader-provenance-20261022/apps/muyon_android`:

```sh
JAVA_HOME=/workspace/host-projection-tools/android-build/jdk-17.0.17+10 \
JAVA_TOOL_OPTIONS=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts \
ANDROID_HOME=/workspace/host-projection-tools/android-build/sdk \
ANDROID_USER_HOME=/workspace/host-projection-tools/android-build/android-user-home \
GRADLE_USER_HOME=/workspace/host-projection-tools/android-build/gradle-user-home \
MUYON_UI_GRADLE=/workspace/host-projection-tools/android-build/gradle-8.13/bin/gradle \
bash ./gradlew --no-daemon --console=plain --stacktrace :app:compileDebugKotlin
```

Raw final log: `evidence/android-restored/systemtrust-compile.log`. Earlier failures preserved separately, including SDK location missing, runtime-only Java, and full JDK trust chain. Some resources are UP-TO-DATE from earlier real task executions; final compileDebugKotlin was executed, not skipped/cached.

## Boundaries and exact remaining blocker

No APK, native library verification, emulator/device test, screenshot or >30s actual reading acceptance claimed. No model/search/business request, deployment, merge, credentials or historical unknown ledger changes. Production verified=false remains unchanged. No main/develop/PR101/Claude edits.

Reader compile is no longer NOT_RUN; it is a reproduced source-level FAIL. Exact target `apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/shell/RequestCandidates.kt:24` calls desktop JSONObject.similar, absent from real Android JSONObject. This is Shell-owned, not Host/Service scope. Pending Shell owner: preserve strict nested observation equality with Android-supported APIs and regression coverage; do not drop the equality check or substitute success. Host did not edit/exclude this file or add a stub. After a fixed Shell commit, parent can compose exact dependencies and rerun. Original native reconcile/stop/handoff/initial admission, IPC/PFD and physical Activity/long-reading gaps still apply.

Raw Gradle logs intentionally retain original trailing spaces (daemon-stop message); full staged diff check reports those evidence-only whitespace warnings. Markdown check and production-source identity checks pass. Logs were not sanitized into different output.

Independent read-only review: no new Important finding; candidate source identity, byte-identical raw logs, official archives/checksums, actual SDK android.jar bytes, unchanged gates and compile-result boundaries checked. See evidence/android-restored/independent-review.log. Reviewer independently used javap to confirm Android JSONObject has no similar method. No new full compilation rerun was represented as performed by reviewer.
