# Independent follow-up review — cancellation identity/CAS

Reviewed implementation/test commit: `4d3b80115dc79ab5829d7e3d82afc1086a302fdb`.
Previous API baseline: `c7c0d4729d034eb3d644e8945a56ca7dba467ff4`.
Reviewer: independent non-author `independent_contract_review`. This report transcribes the returned review; the reviewer did not modify the repository, commit, push or access real requests.

Conclusion: no remaining blocker found for this scoped offline cancellation repair. This supersedes the old scope-only API's review for the Important parent finding. It is not production UI/persistence acceptance or merge permission.

## Independent execution

```sh
KOTLINC=/tmp/muyon-contract-toolchain/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/components/run-offline.sh
git diff --check c7c0d4729d034eb3d644e8945a56ca7dba467ff4..4d3b80115dc79ab5829d7e3d82afc1086a302fdb
```

Both exit 0. Standalone suite: 20 groups PASS. Original complete independent stdout/stderr is copied without editing to [evidence/cancel-independent-green.log](evidence/cancel-independent-green.log).

Reviewer checked ComponentContracts.kt lines 187–197: exact pending identity equality and current CAS revision before mutation, no remaining `requestCancel(scope)` overload, idempotent current-CAS duplicate, stale duplicate rejection and no terminal receipt fabrication. Tests cover late A with both A's stale CAS and B's current CAS; B's complete snapshot remains unchanged. Every identity field, wrong scope and stale revision are rejected. Unknown keeps original lookup identity, held costs and nullable actual fees, without a resubmission decision.

## Independently reproduced original defect

Reviewer extracted old implementation with `git show` into a temporary directory, compiled an independently authored probe (exit 0), then ran it and obtained the expected invariant failure (exit 1). Original source: [evidence/muyon-cancel-independent-legacy.kt](evidence/muyon-cancel-independent-legacy.kt). Original complete output: [evidence/cancel-independent-legacy-red.log](evidence/cancel-independent-legacy-red.log).

```text
captured_cancel_intent=intent-A; current_pending=intent-B
before_phase=PENDING; after_phase=CANCEL_REQUESTED
before_revision=6; after_revision=7; same_identity=true
```

The assertion fails `Late cancel for attempt A changed pending attempt B`. This is an in-memory synthetic reproduction, not an executed remote cancellation. User explicitly requested original test outputs and independent review to be committed; this authorization applies to the scoped synthetic outputs here.

Reproduction instructions for the preserved probe, from the task worktree (the last command is expected exit 1):

```sh
probe_dir=$(mktemp -d /tmp/muyon-cancel-legacy.XXXXXX)
git show c7c0d4729d034eb3d644e8945a56ca7dba467ff4:apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/components/ComponentContracts.kt > "$probe_dir/ComponentContracts.kt"
/tmp/muyon-contract-toolchain/kotlinc/bin/kotlinc "$probe_dir/ComponentContracts.kt" docs/tasks/chat-component-contracts-20261022/evidence/muyon-cancel-independent-legacy.kt -jvm-target 17 -Werror -include-runtime -d "$probe_dir/legacy.jar"
java -jar "$probe_dir/legacy.jar"
```

Do not compile the legacy probe against the new API or add it to the app test source set: it intentionally demonstrates the removed signature only at the old immutable source.

## Remaining boundaries

Gradle 8.13 is absent; Android build/unit/lint/device verification remains NOT_RUN. Local reducer snapshots do not establish durable persistence or UI integration. No ChatScreen/MainActivity/build files or unrelated tasks changed. Old two unknown requests and CNY0.002620 reservation remain unchanged. No model/search, live lookup/cancel, credential, permission, paid, deployment, main/develop merge or I04 operation occurred. Leader B is still the only develop integrator.

Reviewed implementation SHA-256: `436018795e90f1514e0e3eade39d13c1b1be1be2dc4dcb3dfbf9b99e03368900`.
