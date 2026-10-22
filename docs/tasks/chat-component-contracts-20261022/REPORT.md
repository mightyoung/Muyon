# MU-01 / MU-04 / PX-09 — offline component contract

Status: offline contract implemented; production integration and Android acceptance NOT_RUN.
Branch: `task/chat-component-contracts-20261022`. Base: `f4781e16ddf4e542b983fbd77f266a0071148255`.

## Inputs and repository checks

Read the full 182-line `libfile_d1ffab06dfa4819180f0affb933237bf` (three-product plan) and full 173-line `libfile_03bfe1916f4881918b028ae0acac8bfd` (Muse specification), both with `has_more=false`. Read task index, current status, Leader handover/review rules, Android refactor planning and 20261021 repair ledger, ordinary-chat CURRENT, and frontend/service handovers. No AGENTS.md exists in the checked-out candidate tree or initial workspace search.

`git ls-remote origin` verified candidate `codex/muyon-android-refactor` at the exact base above; main was `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`, develop was `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`. Task remote did not exist. Initial `/workspace/Muyon` branch `work` was clean at main's SHA; work was isolated in `/workspace/muyon-chat-contracts`, preserving that checkout. Main/develop are not modified or merged.

## Delivered contract

Only new files in `chat/components/`, the corresponding independent `src/test/.../components/`, and this task's reports are written. No ChatScreen.kt, MainActivity.kt, build, manifest, IPC or other task files changed; no dependencies added to the app.

- Finite component kinds and action types; strict parsed-map decoder rejects missing/extra keys, unsupported schema/kind/action, malformed integers/IDs, duplicate IDs, executable source URL disguises, oversized text/action lists. Current input is a bounded already-parsed map, not a JSON parser. The host must bound bytes before parsing. IDs use ASCII letters/digits/underscore/dot/hyphen, length 1–128; JSON adapter must preserve integer types.
- Host supplies workspace/conversation/project/agent/mounted-generation scope. Component/message/revision and CAS state revision are bound to every original submission, together with attempt/action/intent and a SHA-256 digest of length-prefixed sorted local values. This digest is local contract identity, not a replacement for host business/disclosure byte digests.
- Local edits modify draft only. Compose yields input text only; source actions yield a version/page reference only; host actions yield `TrustedHostReviewRequired` with no permission or arbitrary method name. Only `submit_local` records a pending submission.
- `SubmitDecision` distinguishes newly recorded local pending, duplicate pending, original lookup, and historical receipt. Duplicate clicking never produces a second `NewPending`; unknown/cancel-requested only return lookup. Parameters cannot change while unresolved. Confirmed terminal results allow explicit redo with a fresh attempt and fresh intent while retaining previous receipts.
- Pending, draft and committed values are separate. Cancellation intent is not success. Only a matching trusted protocol-1 original receipt can commit local values; unknown retains original identity and held/unknown actual cost. Repeated identical terminal receipt is idempotent; contradictory terminal callbacks fail closed. Historical receipt does not establish the current state of a business record.
- Snapshot values are defensive, unmodifiable copies; restore validates outer and nested identities, values/digest, attempt uniqueness and pending/history relationships. Scope remount/rebind is deliberately unsupported: a future host adapter must validate and explicitly handle it.

`ComponentLedger` is an offline in-memory reducer, not a second durable business/request ledger. `snapshot/restore` provide a contract; no database, disk serializer, crash durability or process-restart acceptance is claimed. Save-before-dispatch, storage failures and durable CAS must be implemented by the existing host owner. A `NewPending` must be durably stored before any local write; persistence failure keeps the original draft and performs no write. None of these DTOs grant authority; observations come only from a trusted existing host adapter.

## Existing host mapping; cross-owner patch plan (not applied)

Static verification at base ChatScreen.kt:

- Lines 40–45 persist original request identity; 82–106 guard conversation/project generations. Future adapter must retain these identities and invalidate stale previews/callbacks.
- Lines 117–151 use `chat_lookup` on the original request and preserve unknown/held costs. `Recovery.LookupOriginal` is only a policy result; it does not call IPC. Local component intents must never be substituted for chat request IDs. The current reducer accepts only local-submit receipts; chat request observations need an explicit, separately reviewed mapper.
- Lines 153–172 keep `chat_prepare`/`chat_tool` separate. Model action names must never be passed as IPC method names. `TrustedHostReviewRequired` may only open the existing host preview path.
- Lines 174–211 verify original business `lookup` protocol/scope/intent/committed. Map verified facts to history without treating them as the current record.
- Lines 396–424 preserve full outbound preview, send_allowed, pricing proof and durable original identity before confirmation; 425–467 keep business modification and disclosure confirmations separate. No local selection or compose proposal may satisfy either confirmation.

Any production wiring would require ChatScreen.kt and likely existing host persistence/adapter ownership outside this task. Proposed next patch: host-owned bounded JSON adapter; source locator/permission check; reducer snapshot persistence with CAS and failure/restart tests; proposal-to-existing-preview mapping; trusted original-receipt mapper; Compose projection with no authority. Parent/Leader B must assign those files before implementation. This branch does not change or claim that UI/business wiring.

## Verification and retained failures

Compiler: isolated JetBrains Kotlin JVM 2.1.20, JRE 21, JVM target 17, `-Werror`. Compiler downloaded to `/tmp/muyon-contract-toolchain` for verification only; no repo build configuration changed. Test runner has no downloads/network and uses caller-provided `KOTLINC`.

Run from the task worktree:

```sh
KOTLINC=/tmp/muyon-contract-toolchain/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/run-offline.sh
git diff --check
bash apps/muyon_android/gradlew --offline :app:testDebugUnitTest
```

- Standalone contract suite: PASS 16 named groups, including 16 simultaneous clicks with one original identity and one state transition. No sleeps, provider/IPC or socket fixtures. Compiler warnings are errors.
- `git diff --check`: PASS.
- Gradle: exit 2, `NOT_RUN: set MUYON_UI_GRADLE to the existing Gradle 8.13 executable.` Full app compilation/unit suite, Android lint, APK, native/model inputs, emulator/device/TalkBack and production persistence tests remain NOT_RUN; the standalone test main is not automatically registered in Gradle. No build files changed to pretend otherwise.
- Test-first initial absence RED: source/contracts missing. First stub RED: unimplemented decoder. Strict compilation exposed a data-class copy visibility warning; replaced it with an ordinary class. Actual schema assertion RED then reproduced unsupported versions being accepted before the schema-version guard was completed.
- Independent review reproduced ambiguous duplicate submit decisions, cross-conversation nested restored identities, and changed restored values retaining the old digest. The new restore regression first failed `Expected rejection`. Fixed with typed decisions and full nested restore checks; all 16 groups now PASS. Raw logs stay in `/tmp`, not committed, per repository review rules. Further review caught UTF-8 replacement aliasing for lone UTF-16 surrogates and forged committed/reused-intent restore paths; each received a failing regression and is now rejected, while valid emoji remains accepted. Final independent fixed-source result is recorded separately.

## Holds and remaining blockers

Old two real requests remain unknown, retained reservation CNY0.002620, actual usage/fees unknown. No lookup against real state, retry, reset, model/search call, credentials, new permission, deployment or paid action occurred. No I04 or containing-suite retry. This branch has no network/IPC implementation.

Overall product PARTIAL/HOLD is unchanged. Current candidate's CI/device/release evidence does not transfer to this branch. Missing Gradle/tooling, approved native/model inputs, durable host adapter, schema transport integration and device acceptance block any production-ready claim. Leader B remains the only develop integrator; this task only commits and normally pushes its independent branch.
