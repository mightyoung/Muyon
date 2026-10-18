#!/usr/bin/env bash
set -euo pipefail
cd /workspace/ocr-v6-followup/experiments/redesign/ocr-v6-adapter
export JAVA_HOME=/workspace/ocr-tools/jdk-17.0.20.1+1
export GRADLE_USER_HOME=/workspace/ocr-tools/gradle-home
export ANDROID_HOME=/workspace/ocr-tools/android-sdk12
export ANDROID_USER_HOME=/workspace/ocr-tools/android-user
export RUSTUP_HOME=/workspace/ocr-tools/rustup
export CARGO_HOME=/workspace/ocr-tools/cargo
export OCR_ASSETS=/workspace/ocr-assets
export PYTHONPATH=/workspace/ocr-python
GRADLE=(/workspace/ocr-tools/gradle-8.13/bin/gradle -Dhttps.proxyHost=proxy -Dhttps.proxyPort=8080 -Dhttp.proxyHost=proxy -Dhttp.proxyPort=8080 -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts --no-daemon)
git rev-parse HEAD > evidence/followup-tested-sha.txt
/workspace/ocr-tools/cargo/bin/cargo test --locked --manifest-path core/Cargo.toml > evidence/fixed-rust.log 2>&1
python -m unittest discover -s checks -p 'test_*.py' > evidence/fixed-python.log 2>&1
"${GRADLE[@]}" test --rerun-tasks > evidence/fixed-kotlin.log 2>&1
"${GRADLE[@]}" -p android-packaging :adapter:assembleDebug :probe:assembleDebug --rerun-tasks > evidence/fixed-android-build.log 2>&1
python checks/native_packaging_audit.py /workspace/ocr-tools/downloads --apk android-packaging/probe/build/outputs/apk/debug/probe-debug.apk --adapter-aar android-packaging/adapter/build/outputs/aar/adapter-debug.aar --ndk "$ANDROID_HOME/ndk/28.2.13676358" --require-static-pass > evidence/fixed-package-audit.json
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -v -c -P 16 4 android-packaging/probe/build/outputs/apk/debug/probe-debug.apk > evidence/fixed-zipalign.log 2>&1
env -u PYTHONPATH bash checks/native-parity-desktop/run.sh > evidence/fixed-parity.log 2>&1
