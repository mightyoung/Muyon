#!/usr/bin/env bash
# Pure JVM contracts only. Never downloads, invokes providers or opens Android.
set -euo pipefail
checksum=(sha256sum)
command -v sha256sum >/dev/null || checksum=(shasum -a 256)
root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc}
json_jar=${JSON_JAR:-/workspace/publicui-tools/json-20250517.jar}
command -v "$compiler" >/dev/null || { echo 'BLOCKED: kotlinc unavailable' >&2; exit 127; }
[[ -f "$json_jar" ]] || { echo 'BLOCKED: actual org.json JVM artifact required' >&2; exit 2; }
echo '3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796  '"$json_jar" | "${checksum[@]}" -c -
out=$(mktemp -d /tmp/muyon-publicui-checks.XXXXXX)
trap 'rm -rf "$out"' EXIT
# Immutable owner fixture, kept out of this task's fact definitions.
git -C "$root" show 6e7f774b1559a0a9693eeb195ba13c9ded561993:docs/contracts/public-services-v02/fixtures/types.json > "$out/types.json"
echo 'af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5  '"$out/types.json" | "${checksum[@]}" -c -
sources="$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/publicservices"
checks="$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices"
"$compiler" -Werror -jvm-target 17 -classpath "$json_jar" "$sources"/*.kt "$checks"/PlanValidationChecks.kt "$checks"/PresentationStateChecks.kt -include-runtime -d "$out/checks.jar"
java -cp "$out/checks.jar:$json_jar" com.mightyoung.muyon.product.ui.publicservices.PlanValidationChecksKt "$out/types.json"
java -cp "$out/checks.jar:$json_jar" com.mightyoung.muyon.product.ui.publicservices.PresentationStateChecksKt
