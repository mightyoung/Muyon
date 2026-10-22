# Request observation independent review

Reviewed only the uncommitted compatibility changes in `RequestCandidates.kt` and
`RequestCandidateChecks.kt`, against HEAD `c0c2dc994df099c36c83813adf8410dac999d943`.
Unrelated reader consent changes are outside this fix and review. No production
files changed by the reviewer; no commit, merge, push or real service request.

## Conclusion

No blocking or Important issue found in this bounded change. Replacing
`JSONObject.similar` with the Android-available `length/keys/has/opt` APIs resolves
the specific compatibility dependency while retaining the whole duplicate
observation check. The checked String cast also handles the Android fork's raw
iterator. Equal key counts plus `has` distinguish missing keys from explicit NULL;
NULL identity and exact permitted scalar class/value avoid coercion. All keys,
including facts not rendered on screen, participate. Nested values fail closed;
64 keys is the maximum. Candidate scope/original identity, binding=NULL,
can_execute=false and can_cancel=false guards remain in place. No new card action
or transport authority is introduced.

## Actual independent verification

From `/workspace/muyon-ui-shell`, executed the existing runner twice:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/android-json-0.0.20131108.vaadin1.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh

KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

Both exit **0**; each produced three PASS results: actual Runtime/controller,
request candidates, and cold persistence projection. Compilation uses `-Werror`
and JVM target17. The fake port forbids unexpected native calls and the injected
transport throws if called. Negative tests cover hidden observation fields,
missing/NULL/type mismatches and structured objects; positive tests cover key order
and valid candidate preservation. `git diff --check` also exit0.

The independent log records every runner source/script hash before and after both
runs, each dependency hash, exact command and raw output. **All inputs unchanged.**
Reviewed file SHA256:

- RequestCandidates.kt: `c30ca08815352a901bb45ddbc428241ebea89279b8f68bf221bf98e8afe4d7c2`
- RequestCandidateChecks.kt: `a11eeccfb504ad5e673eefe6d5ae82c74d544e86a974f4608ce3a2cd6c303e25`

Evidence: `evidence/request-observation-independent.log`.
Separately inspected the author's `request-observation-original-platform-red.log`:
the old source failed on unresolved `similar`; that RED was not rerun by this
reviewer and is not counted as independent execution.

## Limits and remaining blockers

This is actual JVM compilation/execution against a real Android org.json fork,
plus JSON-java compatibility, not an Android Gradle/APK/device PASS. The target
Android CI must reach a terminal result on the exact isolated fix commit. Existing
local AGP8.11.1 plugin resolution and SDK filesystem blockers are not resolved by
these pure checks. No Android build was run by this independent review.

Minor coverage gap: the existing checks do not explicitly exercise 64/65-key
boundaries, Long versus Int, or JSONArray rejection. Their implementation branches
were statically reviewed; they are not claimed as dynamically tested here.
