# Independent lifecycle review

Reviewer read-only against repository; no tests or application actions executed by reviewer. Baseline a150974111afdc716aac3c44ac2cb200a9c1c943. Worktree still changing; final immutable source review pending.

## Pre-execution gates

- BUILD-ONLY CLEAR: `.github/workflows/service-lifecycle-owner.yml` scoped/native jobs and `checks/lifecycle_package.py`. Cargo build/bindgen, android_gate native build/readelf, package explicit assembleLifecycle/assembleLifecycleAndroidTest/lintLifecycle. Imported linux_gate/package_gate modules have main guards; their legacy suites are not invoked. External downloads are pinned development tool/dependency assets, not provider/model traffic. ROOT parents[4] resolves repository.
- CLEAR: exact `cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test service_provider_release -- --nocapture`. Six in-memory metadata tests; no database, HTTP, credential reads or reopen. No broad cargo suite authorized.
- Instrumentation test source inspected: exact LifecycleServiceAdmissionTest class uses actual Service bind/connect and only read-only queries against fresh dedicated admission ledger. No killing processes or changing admission through IPC. Full device gate awaits fixture/build variant review.

## Preliminary implementation assessment

Actual Service reserves unique controller slot before lease acquisition; process host roots retain uncertain constructor outcomes. Lease closes after sealed generated native cleanup, before slot release. Fixed Rust probe is serialized with retirement and calls provider prepare/final_admit, with no transport and no changes to ordinary readiness. Prepared-call Drop releases held reservations; successful consumption disarms release before validating returned metadata. Existing v1 expired state preserves replay tombstones; no old schema migration.

## Required evidence and limitations

Acceptance must assert individual default-denial/revocation/replay/quota/cancellation results, not infer them from row totals. OnCleaned may be called repeatedly by existing admission API; fixture evidence must deduplicate. Restart must pass existing private file permission checks and preserve receipts/tombstones without resubmission. UI recreation, setup failure, retained-native onDestroy and process-death cases need explicit evidence or remain gaps. Synthetic API26 emulator evidence is not real device/model evidence.

PR86/dependency HOLD remains; PR90 immutable. Denied I04/old task.db to HTTP to original reopen is excluded, including implicit suites. Prior artifact403 must not be retried. No tests executed by reviewer.

## Completed static review and device gate

Full current diff reviewed (Kotlin Service/lease/holder/fixture/build, Rust controller/probe/provider/callback, genuine generated Kotlin API changes, focused test/workflow/package). No blocking defect found for the bounded synthetic metadata lifecycle slice. This is static approval to execute the named new focused acceptance, not a CI/runtime success claim. Base HEAD still a150974111afdc716aac3c44ac2cb200a9c1c943 at review; implementation is uncommitted and requires final frozen SHA association.

DEVICE GATE CLEAR: workflow exact class `com.mightyoung.muyon.androidlab.agentipc.LifecycleServiceAdmissionTest`, one named test. Compile-time lifecycle variant manifest replaces Application; fixture approvals never enter ordinary debug/release. Fixed Rust operation dispatch takes no payload/budget/path/authority IPC fields. Manifest has no INTERNET permission. No new Binder/UI provider operation, no credential-value API, no old state source, no forbidden I04 suite. Package now passes -PmuyonLifecycleInstrumentation=true. Normal Service retirement/rebinding in same private :agent process is allowed fresh-new-schema lifecycle acceptance, not old original-state reopen.

ADDITIONAL NATIVE GATE CLEAR: exact `cargo test --locked --manifest-path experiments/redesign/android-rust-bridge-lab/core/Cargo.toml --test service_lifecycle_probe -- --nocapture`. One fixed fixture with fresh create_dir temporary controller root, memory callback owner, fixed cancellation/admission operations, retirement and post-retirement denial. No legacy test helpers or reopening old state. This is native callback evidence, not durable Android acceptance.

Acceptance source now explicitly asserts exact denial/replay/revoked-credential/success codes and booleans, cancellation expired=1, held=0, consumed/admission=1, matching opaque admission identity, cleanup before rebind, same private process, restart fresh tertiary request fails exhausted ceiling, unchanged durable rows, and final cleanup. Liveness Binder retained for binding lifetime. Earlier onCleaned duplicate notification corrected with atomic one-shot guard. Earlier invalid-reservation release gap corrected by establishing Drop guard before identity validation.

Reviewed mutable source SHA256 snapshots:
- LifecycleFixtureApplication.kt 317897a63613929da81e1e4bf584149e31cdbf189b88d793e15158b404e0b8bf
- LifecycleServiceAdmissionTest.kt 91652b6bccdde581d8b50911043bb922ea09607050864cf43338e4dea8ffc268
- service-lifecycle-owner.yml 6058bebda3b4b854c9346e2a2db16480a894fe4d3619cbabc7f1b12a87ffa553
- lifecycle_package.py 2bfc148419ba93a66633ae28d1b18c243533a142f5a597c1bedc1f387cfcedaf

Evidence observed, not executed by reviewer: /tmp/muyon-service-provider-release.log reports six focused release tests passed. git diff --check clean. Genuine binding regeneration/reproduction and API26 acceptance CI still pending at this review.

Remaining scope gaps: ordinary Application intentionally retains explicit SyntheticLab composition; only lifecycle build exercises Installed owner. No production authority/provider/source bootstrap is installed. No post-reserve credential revocation lifecycle assertion (native post-reserve policy drift covered in isolated test), Activity recreation, injected setup/native constructor failure, held-native onDestroy race or process death/recreation is executed by new Android acceptance. Uncertain native constructor outcomes intentionally pin owner/slot until process exit rather than reopen. SQLite-created file permission compatibility is pending API26 restart evidence. These gaps must remain explicit in final delivery and cannot be described as verified. No real device/model/network evidence exists, and HOLD remains unchanged.

## Final pre-freeze delta review

Latest reviewed changes remain CLEAR: exact two named Rust targets included in scoped CI (6/1 count guards); mandatory Rust release callback implemented by all four test callback implementations and Kotlin adapter; generated API updated; no broad suites introduced. AgentRuntimeService now publishes fixture cleanup evidence only after lease close, host-root removal and successful controller-slot release, preventing acceptance rebinding before slot release.

ActivityScenario.launch(MainActivity).recreate was added while the explicit first Service binding remains live. Read MainActivity -> Application visibility/chats -> AgentServiceClient.visibility/AgentChatReadSession init and MuyonLabShell effects. Startup renders snapshot and bounded UI preferences only; no auto-connect, supplier submit, provider probe, HTTP or old database operation. No UI inputs are synthesized. Activity closes before explicit Service unbind. Boundary gate remains CLEAR; Android acceptance now checks Activity recreation did not bootstrap/close/alter ledger (runtime outcome pending). Remove Activity recreation from the previous remaining-gap list once that CI passes. Setup/native-constructor failure, retained-native onDestroy and process death remain unexecuted Android cases.

Final pre-freeze SHA256 deltas:
- LifecycleServiceAdmissionTest.kt 6b39604a8027069e1f5fe1583e1d9ce31f103671e370b9868ece731b7311a240
- service-lifecycle-owner.yml 1abf1c9da4a6f9b031564fd50d9216433de3180dcb536c43cf183c8a97d9bd7a
- AgentRuntimeService.kt 4deac5a8a2779076602ebdc682eadba503712c54aa92348e083bcf35b12f8721

Observed /tmp/muyon-service-lifecycle-probe.log: exact one native probe test passed. Reviewer's own actions remain reads and scratch report only; no tests run or repo changes.

## Pre-push automatic trigger audit

Independent audit of every .github/workflows file: current branch `lab/service-lifecycle-owner-20261018` matches only dedicated service-lifecycle-owner push branch. Existing ci.yml includes develop/main/task/**/review/** only; choosing lab scope avoids its broad Dart suite without modifying existing workflow. Other automatic push filters require their own explicit task/ui/lab/android-compose/lab/android-rust-bridge/lab/rust-native-read/lab/leaderb/core-review/durable branch identities and do not match this branch. No workflow_run chained triggers exist. verify and package-artifacts remain manual only.

Draft PR to `lab/service-durable-owner-20261018`: ci.yml main/develop and Android Rust bridge develop PR base filters do not match. Android Compose PR workflow can be created by paths but its sole job explicitly requires head prefix lab/android-compose-, which this head lacks; job skips. No forbidden/broad suite auto-execution is expected from this branch push + specified Draft PR base.

Dedicated workflow branch changed only task/service-lifecycle-owner-20261018 -> lab/service-lifecycle-owner-20261018, plus path filters for app/bridge/host code and dedicated workflow; evidence-only docs commit will not match. Previously reviewed exact execution graph remains unchanged. This trigger isolation does not authorize dispatching any existing broad workflow, modifying main/develop, or releasing HOLD. Static pre-push trigger gate CLEAR; waiting frozen source SHA association.

## Frozen-source association

Final static code/spec/pre-execution and push/PR trigger approval associates to immutable source `f8d3bfea3606d187479ed6d16621b342eca74760` on `lab/service-lifecycle-owner-20261018`. Worktree verified clean after commit; no implementation edits after review. Intended Draft PR base `lab/service-durable-owner-20261018` only. Exact focused test/device graph and dedicated path-filtered workflow remain as reviewed above. No blocking static finding; API26/package/native CI outcomes still require terminal evidence and must be tied to this source. Prior limitations/HOLD remain.

## Process-restart scheduling clarification during frozen CI

Read-only assessment of f8d3bfea3606d187479ed6d16621b342eca74760: in-memory fixture ordinal prevents primary/secondary resubmission on normal Service rebind in the same :agent process, as scoped CONTRACT §6 describes. It resets after process death and would automatically attempt the same fixed metadata fixture requests again. Durable uniqueness/quota rejects those attempts, and no transport exists, but rejection is not absence of an automatic resubmission attempt. The unqualified no-auto-resubmit-on-restart requirement is therefore not fully satisfied across process recreation. This is confined to the compile-time fixture driver; ordinary Application has no such automatic probe schedule.

Process-death acceptance remains unrun, and frozen-source CI must not be represented as proof for that case. Recommended follow-up after current CI reaches terminal: use only dedicated-ledger read-only fixture history as a scheduling guard to skip previous primary/secondary operations; never derive approval/authority/budget/path from that history. For a stronger guarantee covering crash before the first reservation, persist an explicit trusted bootstrap-start marker (separate reviewed lifecycle metadata) before invoking probes. Any code change needs new frozen SHA and focused revalidation; preserve f8 results and failures. No running-source edits or new experiments performed by reviewer.

## Follow-up durable schedule and own fixture process-death static gate

First frozen CI run 39129510104 for f8d3bfea3606d187479ed6d16621b342eca74760 was reported terminal SUCCESS before these edits. That evidence remains source-exact. New follow-up changes only LifecycleFixtureApplication and LifecycleServiceAdmissionTest (plus eventual documentation); reviewer executed no tests.

STATIC EXECUTION GATE CLEAR for follow-up two-file diff: fixed Context-derived admission-root marker names, O_EXCL|O_NOFOLLOW 0600 create, bounded exact constant bytes, file fsync and parent directory fsync before first probe. Existing marker opens O_NOFOLLOW and checks fstat regular type/UID/exact mode/exact bounded size and exact content; malformed or partial markers throw before probes, duplicate create races fail closed. Marker history controls scheduling only; compile-time fixed approvals remain unchanged. Both markers -> phase3 has zero native probes and no authority approval replacement; opaque admission identity/counts reloaded only by SELECT from dedicated new ledger. Primary schedule cannot be automatically repeated merely because process-local ordinal reset.

Process.killProcess occurs only after nativeCleaned2/leaseClosed2. Runtime guards require target package exactly com.mightyoung.muyon.androidlab.lifecycle, process exactly its :agent, same current app UID, original observed PID, different instrumentation PID. Test waits that child disappears, binds its own Service anew, verifies distinct new PID/same own UID, phase3, zero probes, empty process-local result proof, same durable receipt and rows. This is expressly the fresh test APK's own child/new schema operation, not denied old script/task.db/HTTP/original-state reopening. No production process target, shell script, credential or network call introduced.

Allowed invocation remains only exact `com.mightyoung.muyon.androidlab.agentipc.LifecycleServiceAdmissionTest` via previously reviewed dedicated API26 workflow, tied to a NEW frozen source SHA. No broad suite or manual legacy workflow dispatch authorized. Need new immutable association and runtime terminal evidence. Remaining limitations: process death is tested after complete native/lease cleanup, not active/in-flight native work; no corruption/partial-marker fault injection or fsync failure acceptance; setup/constructor failure and retained-native onDestroy remain unrun.

Follow-up approval frozen-source association: `afbed6dc6639f72e3356c3b2156cd335c802685d`, clean worktree verified. Diff from f8 changes only the reviewed two fixture/test files plus docs/evidence; dedicated workflow unchanged and isolated lab-branch/Draft-base trigger gate remains valid. Reviewed fixture SHA256 08071bd71869aa9cdc38a8bc6bbad568eadad62ba40d1c32060631f229d4c281; test SHA256 ea90ceb89ecf516758bdc273b7b1a811b5539f6d46c1c8deb815d91c0ba01120. No static blocking finding for exact focused execution; runtime CI pending on this follow-up source. Earlier f8 SUCCESS must remain separately identified. HOLD remains unchanged.

## Compile-failure diagnostic and public-SDK correction gate

Second frozen source afbed6dc6639f72e3356c3b2156cd335c802685d run 39130222418 reported terminal Kotlin compile failure before instrumentation; exact native tests and ABI producers reportedly passed. Failed result remains preserved. Newly attempted artifact retrieval reportedly returned403 once; no reviewer archive retrieval/retry performed. Original compiler diagnostic line is unavailable, so do not assert it was directly observed.

Current three-file correction static gate CLEAR. Public API36 OsConstants listing at /tmp/muyon-api36-OsConstants.txt includes O_RDONLY/O_NOFOLLOW/S_IFDIR and lacks O_DIRECTORY; author separately reported focused public-jar compile reproduction. Replacing O_DIRECTORY by O_RDONLY|O_NOFOLLOW plus fstat of opened directory descriptor (S_IFDIR, same UID, exact0700) before directory fsync preserves durability/no-follow validation with public APIs. This supports the compile diagnosis as inference without claiming recovered CI log details. Existing marker validation, phase scheduling and exact own-process kill test remain unchanged.

lifecycle_package.py still executes identical Gradle arguments/tasks. On failure it reads only its own local combined-build.log, prints regex-matched compiler diagnostic lines with a 16,384-character cap, and bare-raises original exception. No archive/network/suite operation added. Workflow now prints at most four fixed API26_SERVICE_LIFECYCLE_PASS/API26_SERVICE_PROCESS_RECREATION_PASS logcat metadata lines; optional grep cannot replace exact instrumentation OK(1 test)/failure guards. No whole logcat is printed. Trigger matrix unchanged. New frozen-source association/runtime terminal evidence pending.

Third frozen-source approval association: `a971b4f6742eed9aaf93f7ddb9e956278dd7f75c`, clean worktree verified. Delta from afbed contains only reviewed fixture public-SDK correction, package diagnostic wrapper, workflow bounded metadata logging and docs/evidence. Exact named 6+1 native tests / single lifecycle instrumentation class / own private cleaned :agent process-death boundary and isolated lab branch trigger restrictions remain approved. No static blocking finding; runtime terminal evidence pending for a971. First f8 SUCCESS and second afbed compile FAILURE remain separately preserved; HOLD unchanged.

## Final independent completion observation

Read saved direct GitHub run metadata and logs at /tmp/muyon-lifecycle-ci-39130933732/{run.json,jobs.log}; no tests re-executed and no code modified. Run https://github.com/mightyoung/Muyon/actions/runs/39130933732 is completed SUCCESS for exact source `a971b4f6742eed9aaf93f7ddb9e956278dd7f75c`. All four jobs (scoped, arm64-v8a native, x86_64 native, package-device) completed success. Direct log contains actual 6/6 provider-release and 1/1 native-probe PASS outputs, genuine binding reproduction step success, `LIFECYCLE_NATIVE_COMPOSE_PACKAGE_PASS source=a971...`, and actual instrumentation `OK (1 test)`.

Actual API26 emulator metadata lines: :agent PID4592 completed normal Service rebind bootstrap_count2 with admissions1/consumed1/held0/expired1, opaque receipt aa6b36ed-2133-47bb-abee-8a825858ff88. Own fresh fixture process recreation changed PID4592 ->4653; phase3 probe_attempts0 and same receipt. Passing named test includes fixed default denial, credential revocation before prepare, release/replay rejection, exact quota exhaustion, Activity recreation retaining owner, native/lease cleanup before replacement, unchanged durable rows and receipt after normal rebind and clean process recreation. This also resolves the previous API26 SQLite file-mode/reopen compatibility uncertainty for the exercised fixture path.

FINAL VERDICT: no blocking static finding; implementation and observed focused CI satisfy the agreed narrow actual-Service synthetic metadata lifecycle contract. Actual chain is lifecycle Application installation -> private Service slot/owned lease -> genuine generated withHost -> Rust fixed prepare/final_admit/drop -> same Kotlin durable owner -> new-schema SQLite ledger. Ordinary build remains explicit SyntheticLab; no production authority installation or transport is approved. This is emulator/synthetic provider evidence, not real device, real credential or model/network execution.

Explicit remaining gaps: setup/constructor/native cleanup failure injection; onDestroy with retained/in-flight native work or callback race; process death during active or unsettled admission; crash/fault injection during marker writes/fsync; post-reserve credential revocation through Android lifecycle (isolated native policy drift cleanup is covered). Tested process death occurs only AFTER native and owner cleanup. No legacy task.db migration/reopen, forbidden I04 suite, broad Dart suite or PR90 modification was executed by this work. Prior f8 success, afbed compile failure and artifact403 remain preserved, without retry. PR86/dependency HOLD remains, and CI success authorizes no merge/deployment/real provider enablement.

All implementation writers reported stopped. Reviewer is stopped and has no repo writer. Subsequent archive/handoff must be docs-only; executable changes would require renewed review/frozen-source evidence.
