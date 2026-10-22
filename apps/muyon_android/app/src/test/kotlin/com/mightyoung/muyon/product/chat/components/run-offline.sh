#!/usr/bin/env bash
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
output=$(mktemp -d /tmp/muyon-components-test.XXXXXX)
trap 'rm -rf "$output"' EXIT
"$compiler" "$repo"/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/components/*.kt \
  "$repo"/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/ComponentContractsTest.kt \
  -jvm-target 17 -Werror -include-runtime -d "$output/contracts.jar"
java -jar "$output/contracts.jar"
