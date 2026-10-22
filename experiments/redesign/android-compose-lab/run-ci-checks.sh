#!/usr/bin/env bash
set -euo pipefail
lab_dir=$(cd "$(dirname "$0")" && pwd)
gradle_bin=${MUYON_UI_GRADLE:-gradle}
if ! command -v "$gradle_bin" >/dev/null 2>&1; then
  printf '%s\n' 'NOT_RUN: Gradle 8.13 is required; this script does not install tools.' >&2
  exit 2
fi
if [[ -z ${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}} ]]; then
  printf '%s\n' 'NOT_RUN: an existing authorized Android SDK 36 / build-tools 35.0.0 is required.' >&2
  exit 2
fi
export GRADLE_USER_HOME=${MUYON_UI_GRADLE_HOME:-/tmp/muyon-android-compose-gradle}
"$gradle_bin" --no-daemon -p "$lab_dir" :state:check :app:assembleDebug :app:assembleDebugAndroidTest
# Compiles APKs only; no adb, emulator, install or device tests are invoked.
