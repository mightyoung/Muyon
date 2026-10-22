#!/bin/sh
set -eu
# Offline standalone JVM component compilation; this is not an Android build.
lab=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
java_bin=${CANARY_JAVA_BIN:-/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java}
cache=${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1
jar_path() {
    find "$cache/$1/$2/$3" -name "$2-$3.jar" -type f -print -quit
}
compiler=$(jar_path org.jetbrains.kotlin kotlin-compiler-embeddable 2.2.21)
stdlib=$(jar_path org.jetbrains.kotlin kotlin-stdlib 2.2.21)
reflect=$(jar_path org.jetbrains.kotlin kotlin-reflect 2.2.21)
script=$(jar_path org.jetbrains.kotlin kotlin-script-runtime 2.2.21)
coroutines=$(jar_path org.jetbrains.kotlinx kotlinx-coroutines-core-jvm 1.8.0)
annotations=$(jar_path org.jetbrains annotations 13.0)
for jar in "$compiler" "$stdlib" "$reflect" "$script" "$coroutines" "$annotations"; do
    test -f "$jar" || { echo 'Required cached compiler jar missing' >&2; exit 1; }
done
out=$(mktemp -d "${TMPDIR:-/tmp}/ordinary-canary-jvm.XXXXXX")
trap 'rm -rf "$out"' EXIT HUP INT TERM
"$java_bin" -cp "$compiler:$stdlib:$reflect:$script:$coroutines:$annotations" org.jetbrains.kotlin.cli.jvm.K2JVMCompiler \
    -no-stdlib -no-reflect -jvm-target 17 -classpath "$stdlib:$annotations" -d "$out/classes" \
    "$lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/OrdinaryChatCanaryBudget.kt" \
    "$lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/OrdinaryChatReferenceTokenBound.kt" \
    "$lab/checks/ordinary_chat_canary_budget_test.kt" \
    "$lab/checks/ordinary_chat_reference_token_bound_test.kt"
"$java_bin" -cp "$out/classes:$stdlib" com.mightyoung.muyon.androidlab.agentipc.Ordinary_chat_canary_budget_testKt
"$java_bin" -cp "$out/classes:$stdlib" com.mightyoung.muyon.androidlab.agentipc.Ordinary_chat_reference_token_bound_testKt
