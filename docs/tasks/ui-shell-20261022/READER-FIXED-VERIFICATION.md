# Fixed reader JVM regression verification

Exact remote/FETCH_HEAD input:8d2b7931fa6b9194338ec81f1add8110075b92bc.
This report replaces neither the reader author's retained NOT_RUN logs nor Android
acceptance. No reader/service/native/research production source has been edited or
merged by shell; final composition remains pending parent release and the exact
host authority/FD/receipt bridge requested in READER-WIRING-REQUEST.md.

## Fresh reproducible command

From this repository root:

```bash
python3 docs/tasks/ui-shell-20261022/evidence/verify-reader-fixed.py
```

Uses existing verified Kotlin2.2.20, -Werror -jvm-target17 -include-runtime and java -jar.
Each variant extracts real files with git show of the fixed commits into a fresh
temporary directory, compiles before execution and records SHA256 for every input.
No Android/platform stubs, fixture app data, network or new dependency/install is used.
Machine-readable matrix: evidence/reader-fixed-results.json; full command/compiler/
runner output and source hashes in the following unfiltered logs.

| Variant | Actual production inputs | Compile | Runtime | Evidence |
|---|---|---|---|---|
| Final full pure suite | Models/parser/checks all8d2b7931 | exit0 | exit0 PASS | reader-fixed-all-green.log |
| Old inline rPh | Final Models/checks + parser3d2be1e783652735b79e9b58f6461d88ce131dc4 | exit0 | exit1 expected behavior RED, A1 contains 東京とうきょう駅 | reader-inline-phonetic-red.log |
| Old sharedStrings rPh | Same old parser; only preceding inline assertion replaced with actual-value print to reach unchanged shared assertion | exit0 | exit1 expected behavior RED, A1 contains 東京とうきょう駅 | reader-shared-phonetic-red.log |
| Old Highlight clearing | Models3d2be1e783652735b79e9b58f6461d88ce131dc4 + final parser/checks | exit0 | exit1 expected behavior RED at empty-note replacement assertion | reader-highlight-empty-red.log |

The sharedStrings isolation changes test flow only, never production parser behavior;
the exact transformation and changed check-source hash are retained in the script,
log and JSON. The unchanged final whole suite exercises both phonetic paths and
next-cell/string leakage, empty and whitespace highlight-to-null, preserved original
quote, comment blank rejection, NUL and UTF8-size checks. Old3d2 already has the new
navigation policy, allowing the parser/highlight negative controls to compile; it is
not claimed as the pre-navigation UI.

The final full suite also actually executes page-failure ReaderNavigation policy:
known page count permits navigation/retry; unknown count permits retry only;
access loss blocks navigation/retry and loading does not permit retry. Static reading
confirms real Compose prev/next/location use that policy and readAttempt only restarts
the read producer, preserving remembered annotation editors and save coroutine scope.
The old6cda Compose policy gated all those actions on ready and offered no retry,
but no old/new Android page lifecycle was executed. Pure policy PASS is not a behavioral
Android RED/GREEN for transient page failure → retry → retained Unknown lock.

## Actual fixed-source Android attempt

Extracted the complete apps/muyon_android tree from8d2b7931 into a fresh task temp
directory (no feature-branch merge) and ran the existing official Gradle8.13:

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
-p <exact-fixed-source-temp>/apps/muyon_android --offline --no-daemon --console=plain \
:app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest
```

Actual Gradle exit1 before product compilation: com.android.application8.11.1 could
not resolve from configured Google/Maven/Gradle plugin repositories. Full output and
exact source directory: evidence/reader-fixed-android.log. Android product/test
compilation and device execution remain NOT_RUN; no APK, pixel/render, SAX Android,
IME/Back/zoom/page-retry/Unknown-lock/accessibility result is claimed. No SDK install
or retry of the existing read-only filesystem failure, permission/network setting
change, paid CI, credentials or bypass was attempted.

## Next integration

After parent static release, consume this exact reviewed reader SHA and original
host owner's exact authority/storage/receipt bridge. Page retry is read-only and
must never trigger another annotation mutation; old unknown intent reconciliation
must precede editing on re-entry. Empty highlight note is normalized null; source
quote, shared anchor and expected annotation revision remain unchanged. No surrogate
local document database or successful callback is constructed. The separate future
persistent Bot API must also update strict saved/can_save decoder and bind memory
revision + stored revision + actual receipt; enabling a button alone is insufficient.

Independent review: READER-FIXED-REVIEW.md. Whole UI implementation and Android
acceptance remain incomplete; fixed shell feature slice5186917c stays unchanged.
