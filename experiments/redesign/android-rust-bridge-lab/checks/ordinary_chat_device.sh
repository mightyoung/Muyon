#!/usr/bin/env bash
# Only the ordinaryChat synthetic APK and the two explicit new-root tests.
set -euo pipefail
evidence="$RUNNER_TEMP/chat-package"
mkdir -p "$evidence"
source_sha="$(git rev-parse HEAD)"
printf '%s\n' "$source_sha" > "$evidence/source-sha.txt"
printf 'NOT_RUN: instrumentation command has not been invoked\n' > "$evidence/device-result.txt"
: > "$evidence/device-phases.tsv"
phase=sdk
instrumentation_invoked=false
record() {
  printf '%s\t%s\t%s\t%s\n' "$source_sha" "$phase" "$1" "$2" | tee -a "$evidence/device-phases.tsv"
}
finish() {
  rc=$?
  trap - EXIT
  if (( rc != 0 )); then
    record FAIL "$rc"
    if [[ "$instrumentation_invoked" == true ]]; then
      printf 'NOT_VERIFIED: instrumentation command invoked; phase=%s exit=%s; individual test outcomes require this run instrumentation output\n' "$phase" "$rc" > "$evidence/device-result.txt"
    else
      printf 'NOT_RUN: instrumentation command not invoked; phase=%s exit=%s\n' "$phase" "$rc" > "$evidence/device-result.txt"
    fi
  fi
  exit "$rc"
}
trap finish EXIT
begin() { phase="$1"; record START -; }
passed() { record PASS 0; }

begin sdk
export ANDROID_AVD_HOME="$RUNNER_TEMP/muyon-chat-avds"
mkdir -p "$ANDROID_AVD_HOME"
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --install 'platform-tools' 'emulator' 'system-images;android-26;google_apis;x86_64' 2>&1 | tee "$evidence/emulator-setup.log"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
passed

begin avd
sudo chmod a+rw /dev/kvm
printf 'no\n' | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n muyon-chat-api26 -k 'system-images;android-26;google_apis;x86_64' --force
passed

begin boot
"$ANDROID_HOME/emulator/emulator" -avd muyon-chat-api26 -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect > "$evidence/emulator.log" 2>&1 &
timeout 300 adb wait-for-device
for attempt in $(seq 1 120); do if [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; then break; fi; sleep 2; done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
test "$(adb shell getprop ro.build.version.sdk | tr -d '\r')" = 26
adb shell input keyevent 82
passed

begin install
adb install "$evidence/app-lifecycle.apk"
adb install "$evidence/app-lifecycle-androidTest.apk"
passed

begin instrumentation
# This proves command invocation only; it does not assert that Android started a test.
instrumentation_invoked=true
printf 'NOT_VERIFIED: instrumentation command invoked; awaiting runner evidence\n' > "$evidence/device-result.txt"
timeout 240 adb shell am instrument -w -r -e class com.mightyoung.muyon.androidlab.OrdinaryChatServiceLoopTest,com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatOwnerContractTest com.mightyoung.muyon.androidlab.ordinaryChat.test/androidx.test.runner.AndroidJUnitRunner | tee "$evidence/instrumentation.log"
passed

begin result
grep -F 'OK (2 tests)' "$evidence/instrumentation.log"
if grep -E 'FAILURES|INSTRUMENTATION_FAILED|Process crashed' "$evidence/instrumentation.log"; then exit 1; fi
printf 'PASS: actual Compose Send to private Service same Rust Agent plain fake provider response; synthetic, no network/model call\n' > "$evidence/device-result.txt"
passed
