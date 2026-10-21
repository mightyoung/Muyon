#!/bin/sh
# Reproducible product native input directory. Never copies laboratory libraries.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${ANDROID_HOME:?Set ANDROID_HOME to the installed SDK}"
: "${MUYON_NATIVE_OUTPUT:?Set an absolute task-owned output directory}"
case "$MUYON_NATIVE_OUTPUT" in /*) ;; *) exit 2 ;; esac
ndk="$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin"
source_id=$(git -C "$repo" rev-parse HEAD)
# Include all product sources, even a reviewable uncommitted implementation.
input_hash=$(cd "$repo" && find crates apps/muyon_android/app/src apps/muyon_android/ml-native -type f ! -path '*/target/*' -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256 | cut -d ' ' -f1)
export MUYON_BUILD_ID="$source_id:$input_hash"
export CARGO_TARGET_DIR="$MUYON_NATIVE_OUTPUT/target"
export RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384'
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk/aarch64-linux-android26-clang"
export CC_aarch64_linux_android="$CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER"
export AR_aarch64_linux_android="$ndk/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ndk/x86_64-linux-android26-clang"
export CC_x86_64_linux_android="$CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER"
export AR_x86_64_linux_android="$ndk/llvm-ar"
cd "$repo/crates"
cargo build --offline --locked -p muyon-android-ffi --target aarch64-linux-android --target x86_64-linux-android
mkdir -p "$MUYON_NATIVE_OUTPUT/jni/arm64-v8a" "$MUYON_NATIVE_OUTPUT/jni/x86_64"
cp "$CARGO_TARGET_DIR/aarch64-linux-android/debug/libmuyon_android_product.so" "$MUYON_NATIVE_OUTPUT/jni/arm64-v8a/"
cp "$CARGO_TARGET_DIR/x86_64-linux-android/debug/libmuyon_android_product.so" "$MUYON_NATIVE_OUTPUT/jni/x86_64/"
: "${MUYON_ML_OUTPUT:?Build local model JNI with build-ml-native.sh and set MUYON_ML_OUTPUT}"
sh "$repo/apps/muyon_android/build-ml-native.sh"
for abi in arm64-v8a x86_64; do
    cp "$MUYON_ML_OUTPUT/jni/$abi/libmuyon_local_embedding.so" "$MUYON_NATIVE_OUTPUT/jni/$abi/"
done
printf '%s\n' "$MUYON_BUILD_ID" > "$MUYON_NATIVE_OUTPUT/build-id.txt"
cd "$MUYON_NATIVE_OUTPUT/jni"
shasum -a 256 arm64-v8a/*.so x86_64/*.so > "$MUYON_NATIVE_OUTPUT/SHA256SUMS"
