#!/usr/bin/env bash
# Fixed owner test projection only. No downloads, JSON dependency, engine or host.
set -euo pipefail
checksum=(sha256sum)
command -v sha256sum >/dev/null || checksum=(shasum -a 256)
root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc}
command -v "$compiler" >/dev/null || { echo 'NOT_RUN: approved existing Kotlin compiler unavailable' >&2; exit 2; }
out=$(mktemp -d /tmp/muyon-d2-values.XXXXXX)
trap 'rm -rf "$out"' EXIT
fixed=c95bc6a881bf721a982f907f1bd0bd37031dec40
git -C "$root" show "$fixed:crates/muyon-core/tests/fixtures/public_pipeline.json" > "$out/values.json"
git -C "$root" show "$fixed:crates/muyon-core/tests/fixtures/public_pipeline.values.tsv" > "$out/values.tsv"
echo '4f7fcb8f988ee390b6f8fffa39603e6b92f8d1e7ccb13667c414906a247d3cf5  '"$out/values.json" | "${checksum[@]}" --check --status
echo '547e83849749b77397e460876da78ae1d881e4a58ae6c60151d1a99cc321412c  '"$out/values.tsv" | "${checksum[@]}" --check --status
src="$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/services/documents"
checks="$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/services/documents"
"$compiler" -Werror -jvm-target 17 "$src/IndexCompatibility.kt" "$checks/IndexCompatibilityChecks.kt" -include-runtime -d "$out/checks.jar"
java -jar "$out/checks.jar" "$out/values.tsv"
