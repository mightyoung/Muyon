# Authorized toolchain recovery: exact blockers before SDK acceptance

Product candidate unchanged:043bed97e218bc25202a803aff3c0de1a5da031f, verified
matching origin/task/ui-shell-20261022 before this evidence-only continuation.
PR101 fixed214b4031deb38ca7dfd35ee86396089eb48157d5 and main/develop untouched.
No application source was changed. No current runtime/Compose preview screenshot
exists, so no PNG upload or confirmed Library file ID is claimed.

## Completed, authorized non-SDK work

Existing JDK21, official Gradle8.13 and Kotlin2.2.20 caches survive; no duplicate
installation. Gradle distribution SHA256 revalidated against project's fixed pin:
20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78.
Rust/cargo absent from PATH. SDK cache contains command-line-tools23.0 only, with
no platform, build-tools, adb, emulator, system images or accepted-license records.
Prior CLI bootstrap failed creating its internal bin dir with read-only filesystem;
no repeat installation, HOME override, security/permission change or bypass here.

Actual online compile command (from apps/muyon_android):

```bash
ANDROID_HOME=/workspace/ui-shell-tools/sdk \
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
./gradlew --no-daemon --console=plain :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin
```

Exit1 after1m39s, unresolved com.android.application8.11.1 before application/test
compilation. Raw toolchain-recovery-gradle-online.log. A separate `help --info`
diagnostic with10-second connection/socket timeouts records JVM SocketException:
Network is unreachable for dl.google.com and repo.maven.apache.org. The direct
JVM route is not usable in this environment; this is a network failure, not an
automatic approval denial. No proxy/security/network setting or credentials were
changed to work around it. Diagnostic exit1 after1m40s; log retained as toolchain-recovery-gradle-info.log.

Existing permitted curl route independently downloaded the exact official AGP8.11.1
POM successfully to /workspace/ui-shell-tools/recovery-agp-8.11.1.pom. This does not
mean Gradle dependencies, SDK or product are restored. Official repository XML and
AOSP system-image metadata were fetched read-only; no SDK binary package downloaded.

## SDK agreement: explicit acceptance pending, not inferred from install approval

The latest parent authorization specifically says to report new SDK terms and not
automatically accept them. No accepted-license record exists in this task SDK.

Exact official sources:

- Current command-line download terms:
  https://developer.android.com/studio#terms — page text dated2026-04-28.
- Actual package-manager agreement:
  https://dl.google.com/android/repository/repository2-1.xml — license element
  `android-sdk-license`, text dated2019-01-16, SHA256
  1f8729233617b193fd619213792ae16a41b95d2bbbf525dfe66998252ba68b16.
  Download page and repository text have different dates; they are not declared
  interchangeable. No full external agreement text copied into this repository.
- AOSP runtime-image repository:
  https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml.
  system-images;android-26;default;x86_64 revision1 refers to android-sdk-license.

Precise requested next acceptance scope: permit acceptance of the applicable
Android SDK License Agreement for installing only stable project-required SDK
packages in /workspace/ui-shell-tools/sdk: base platform Android36 revision2
(not extension preview), build-tools35.0.0, stable platform-tools37.0.1, stable
emulator37.2.12 and the AOSP API26 x86_64 runtime image. If a restored command-line
tool prompts the2026-04-28 agreement, obtain acceptance of that exact presented
text too rather than reuse/invent an accepted-license hash. No preview license,
Google Play image, remote device/account or paid service is requested. Installation
still requires the authoritative package manager's actual prompt/manifest check.
This is a concrete legal acceptance boundary from the parent's instruction,
not a newly invented general confirmation policy. No `yes` pipe, license hash
file creation, --accept flag or silent acceptance was performed.

Exact candidate sizes/checksums/URLs and license refs, including excluded preview
entries, are preserved in evidence/toolchain-recovery-packages.json. Official
metadata lists emulator37.3.5 under preview license; it is EXCLUDED from this plan.
The candidate catalog is explicitly NOT installation input, with per-entry selection
labels; no script installs the catalog. Repository-license and download-page URLs
are separate fields, and the license digest names the2019 repository text only.

## No KVM: software route assessed, not asserted working

Host x86_64, cgroup CPU quota4cores, about17GiB available RAM,29GiB workspace disk,
/dev/kvm absent. No hardware/security/network enablement was attempted. Official
command-line docs describe `-accel off` plus ANDROID_I_WANT_MY_TCG=yes for software
VM emulation; they explicitly call it unsupported and very slow:
https://developer.android.com/studio/run/emulator-commandline#system
Software GPU mode is documented separately:
https://developer.android.com/studio/run/emulator-acceleration#accel-graphics.
These ordinary process-level settings do not enable KVM, disable SELinux or change
network access. They are only a possible bounded trial after SDK/license recovery,
not a recorded emulator start. No deprecated -no-accel workaround is planned.

If allowed and tools become available, first inspect that exact emulator's help,
then try one task-owned AOSP API26 x86_64 AVD with software rendering,2GiB guest RAM,
no snapshot/window/audio, normal SELinux and normal environment networking. Bound
boot time and collect real boot completion/adb/device/API/font properties before
capture. Current resources appear sufficient to attempt; performance/success is
unknown. No image downloaded or emulator process launched yet, due to license gate.

## Remaining concrete work

SDK agreement acceptance is PENDING, not denied and not uncertain. Gradle online
compile has FAILED before compilation; diagnostic is separate from application
failure. Actual candidate APK/test APK and their source/native/model evidence must
be produced or supplied by the authorized build owner; no existing trusted current
APK/native inputs found here. No product gate is disabled to fabricate an APK.

After recovery: compile043bed semantics first, run device tests and capture menu,
main-Agent chat, bubbles/cards, Bot progressive configuration, group leader preview,
and light/dark themes from exact recorded source. Retain synthetic-fixture labels
where needed, no invented backend state. Record runtime versus Compose preview,
full SHA, device/API/font and image hashes. Then use the currently available Library
upload route from this consuming environment; only successful per-PNG create/finalize
results may become confirmed library_file_ids. No IDs currently exist for this batch.
