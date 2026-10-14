#!/usr/bin/env bash
# Invoke only with an explicitly authorized connected test device/runner.
set -euo pipefail
: "${ANDROID_SERIAL:?Set ANDROID_SERIAL for the authorized Android test runner}"
adb_bin=${ADB:-adb}
package=$(cd "$(dirname "$0")" && pwd)
(cd "$package" && sha256sum -c SHA256SUMS)
abi=$("$adb_bin" -s "$ANDROID_SERIAL" shell getprop ro.product.cpu.abi | tr -d '\r')
case "$abi" in arm64-v8a|x86_64) ;; *) echo "unsupported ABI: $abi" >&2; exit 2;; esac
remote=/data/local/tmp/muyon-spike01-independent
"$adb_bin" -s "$ANDROID_SERIAL" shell mkdir -p "$remote"
"$adb_bin" -s "$ANDROID_SERIAL" push "$package/probe-dex.jar" "$package/$abi/libspike01_bridge_lab.so" "$package/$abi/libjnidispatch.so" "$remote/"
"$adb_bin" -s "$ANDROID_SERIAL" shell "getprop ro.build.fingerprint; getprop ro.build.version.sdk; getconf PAGE_SIZE; sha256sum $remote/*.so $remote/probe-dex.jar; CLASSPATH=$remote/probe-dex.jar LD_LIBRARY_PATH=$remote /system/bin/app_process $remote spike01.runner.Probe $remote"
