#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${ANDROID_HOME:?Set ANDROID_HOME}"
ndk="$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk/aarch64-linux-android26-clang"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ndk/x86_64-linux-android26-clang"
export CC_aarch64_linux_android="$CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER"
export CC_x86_64_linux_android="$CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER"
export AR_aarch64_linux_android="$ndk/llvm-ar"
export AR_x86_64_linux_android="$ndk/llvm-ar"
export RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384'
export RUSTUP_TOOLCHAIN=1.93.1
cd "$repo/crates"
cargo build --locked -p muyon-study-ffi --target aarch64-linux-android --target x86_64-linux-android
for pair in 'aarch64-linux-android arm64-v8a' 'x86_64-linux-android x86_64'; do
    set -- $pair
    mkdir -p "$repo/apps/study_android/app/src/main/jniLibs/$2"
    cp "${CARGO_TARGET_DIR:-target}/$1/debug/libmuyon_study.so" "$repo/apps/study_android/app/src/main/jniLibs/$2/"
done
python3 "$repo/apps/study_android/native_identity.py" --write
