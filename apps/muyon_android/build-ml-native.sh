#!/bin/sh
# Fixed CPU-only local embedding runtime; models remain separate build inputs.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${ANDROID_HOME:?Set ANDROID_HOME to the installed SDK}"
: "${MUYON_ML_OUTPUT:?Set an absolute task-owned output directory}"
case "$MUYON_ML_OUTPUT" in /*) ;; *) exit 2 ;; esac
ndk="$ANDROID_HOME/ndk/28.2.13676358"
case "$(uname -s)" in
    Darwin) ndk_host=darwin-x86_64 ;;
    Linux) ndk_host=linux-x86_64 ;;
    *) printf '%s\n' 'Unsupported NDK host' >&2; exit 2 ;;
esac
cmake="$ANDROID_HOME/cmake/3.22.1/bin/cmake"
ninja="$ANDROID_HOME/cmake/3.22.1/bin/ninja"
test -f "$ndk/build/cmake/android.toolchain.cmake"
test -x "$cmake"
mkdir -p "$MUYON_ML_OUTPUT"
# Downloads are opt-in for repeatable offline builds. A local archive must have
# precisely the official pinned archive digest, regardless of its filename.
archive=${MUYON_LLAMA_ARCHIVE:-"$MUYON_ML_OUTPUT/llama-b11763.tar.gz"}
python3 - "$archive" "$MUYON_ML_OUTPUT" "${MUYON_ML_FETCH:-0}" <<'PY'
import hashlib
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import urllib.request

archive, output, fetch = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
commit = 'a01ce9ffc64cf370439d6f861a534a65100133ae'
expected = 'a3d34dba84adbe488c62fb53e0d7398f469d791e6640e88c463f9a23184d2222'
if not archive.is_file():
    if fetch != '1':
        raise SystemExit('Missing pinned llama.cpp archive; set MUYON_ML_FETCH=1 to download it')
    archive.parent.mkdir(parents=True, exist_ok=True)
    fd, part = tempfile.mkstemp(prefix='llama-', suffix='.part', dir=archive.parent)
    os.close(fd)
    try:
        urllib.request.urlretrieve(f'https://codeload.github.com/ggml-org/llama.cpp/tar.gz/{commit}', part)
        if hashlib.sha256(Path(part).read_bytes()).hexdigest() != expected:
            raise SystemExit('Downloaded llama.cpp archive digest mismatch')
        os.replace(part, archive)
    finally:
        Path(part).unlink(missing_ok=True)
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit('Pinned llama.cpp archive digest mismatch')
source = output / 'llama-source'
# Re-extract the verified archive so an edited vendor cache cannot change the
# runtime silently. Only this script-owned generated directory is replaced.
if source.exists():
    shutil.rmtree(source)
source.mkdir()
with tarfile.open(archive, 'r:gz') as tar:
    prefix = f'llama.cpp-{commit}/'
    for member in tar:
        if member.name.rstrip('/') == prefix.rstrip('/'):
            continue
        if not member.name.startswith(prefix) or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsupported entry in pinned source archive')
        relative = Path(member.name[len(prefix):])
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit('Unsafe source archive path')
        target = source / relative
        if member.isdir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as src, target.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            target.chmod(member.mode & 0o777)
            os.utime(target, (member.mtime, member.mtime))
print(f'llama.cpp b11763 {commit}; archive SHA256 {expected}')
PY
for abi in arm64-v8a x86_64; do
    "$cmake" -S "$repo/apps/muyon_android/ml-native" -B "$MUYON_ML_OUTPUT/build-$abi" \
        -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
        -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_static \
        -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON -DCMAKE_BUILD_TYPE=Release \
        -DMUYON_LLAMA_SOURCE="$MUYON_ML_OUTPUT/llama-source"
    "$cmake" --build "$MUYON_ML_OUTPUT/build-$abi" --target muyon_local_embedding --parallel 4
    mkdir -p "$MUYON_ML_OUTPUT/jni/$abi"
    cp "$MUYON_ML_OUTPUT/build-$abi/libmuyon_local_embedding.so" "$MUYON_ML_OUTPUT/jni/$abi/"
    "$ndk/toolchains/llvm/prebuilt/$ndk_host/bin/llvm-strip" --strip-unneeded "$MUYON_ML_OUTPUT/jni/$abi/libmuyon_local_embedding.so"
done
cp "$MUYON_ML_OUTPUT/llama-source/LICENSE" "$MUYON_ML_OUTPUT/LLAMA-LICENSE.txt"
(cd "$MUYON_ML_OUTPUT/jni" && shasum -a 256 arm64-v8a/libmuyon_local_embedding.so x86_64/libmuyon_local_embedding.so) > "$MUYON_ML_OUTPUT/SHA256SUMS"
