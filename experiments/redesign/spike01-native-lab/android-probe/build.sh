#!/usr/bin/env bash
# Existing official toolchain only; no downloads, credential setup or device access.
set -euo pipefail
: "${SPIKE_TOOLS:?Set SPIKE_TOOLS to the isolated installed tool directory}"
repo=$(git rev-parse --show-toplevel)
lab="$repo/experiments/redesign/spike01-native-lab"
export CARGO_HOME="$SPIKE_TOOLS/cargo" RUSTUP_HOME="$SPIKE_TOOLS/rustup" CARGO_TARGET_DIR="$SPIKE_TOOLS/target"
export PATH="$SPIKE_TOOLS/cargo/bin:$PATH"
ndk="$SPIKE_TOOLS/android/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk/aarch64-linux-android26-clang"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ndk/x86_64-linux-android26-clang"
cd "$lab"
cargo test --locked -- --test-threads=1
cargo build --locked --release --lib
cargo build --locked --features bindings --bin uniffi-bindgen
for target in aarch64-linux-android x86_64-linux-android; do cargo build --locked --release --lib --target "$target"; done
mkdir -p "$SPIKE_TOOLS/generated"
"$CARGO_TARGET_DIR/debug/uniffi-bindgen" generate "$CARGO_TARGET_DIR/release/libspike01_bridge_lab.so" --language python --language kotlin --no-format --out-dir "$SPIKE_TOOLS/generated"
cp "$CARGO_TARGET_DIR/release/libspike01_bridge_lab.so" "$SPIKE_TOOLS/generated/"
PYTHONPATH="$SPIKE_TOOLS/generated" python3 -B -m unittest discover -s tests -p test_ffi.py -v
for method in close_session unsubscribe; do for variant in success reject unexpected pause; do PYTHONPATH="$SPIKE_TOOLS/generated" timeout 8s python3 -B tests/probe_h1.py "$method" "$variant"; done; done
"$SPIKE_TOOLS/kotlinc/bin/kotlinc" "$SPIKE_TOOLS/generated/uniffi/spike01_bridge_lab/spike01_bridge_lab.kt" android-probe/Probe.kt -cp "$SPIKE_TOOLS/jna/classes.jar:$SPIKE_TOOLS/downloads/coroutines.jar" -include-runtime -d "$SPIKE_TOOLS/probe.jar"
java -Djna.library.path="$CARGO_TARGET_DIR/release" -cp "$SPIKE_TOOLS/probe.jar:$SPIKE_TOOLS/downloads/jna-jvm.jar:$SPIKE_TOOLS/downloads/coroutines.jar" spike01.runner.Probe
mkdir -p "$SPIKE_TOOLS/dex"
"$SPIKE_TOOLS/android/build-tools/35.0.0/d8" --min-api 26 --lib "$SPIKE_TOOLS/android/platforms/android-35/android.jar" --output "$SPIKE_TOOLS/dex" "$SPIKE_TOOLS/probe.jar" "$SPIKE_TOOLS/jna/classes.jar" "$SPIKE_TOOLS/downloads/coroutines.jar"
package="$SPIKE_TOOLS/android-runner-package"
mkdir -p "$package/arm64-v8a" "$package/x86_64"
(cd "$SPIKE_TOOLS/dex" && zip -q "$package/probe-dex.jar" ./*.dex)
cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/libspike01_bridge_lab.so" "$package/arm64-v8a/"
cp "$CARGO_TARGET_DIR/x86_64-linux-android/release/libspike01_bridge_lab.so" "$package/x86_64/"
for abi in arm64-v8a x86_64; do cp "$SPIKE_TOOLS/jna/jni/$abi/libjnidispatch.so" "$package/$abi/"; done
cp android-probe/run-on-android.sh "$package/"
(cd "$package" && sha256sum probe-dex.jar */*.so > SHA256SUMS)
printf 'Package: %s\nAndroid actual load: NOT_RUN\n' "$package"
