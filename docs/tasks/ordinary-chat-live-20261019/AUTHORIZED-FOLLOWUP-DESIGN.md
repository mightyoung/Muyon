# Explicitly authorized follow-up round

The user explicitly approved the question: add at most2 real requests, at most3
including the original attempt, cumulative ceiling1 CNY, preserve the original
stopped batch/reservation and never resend its request. This is a new trusted
round, not reopening or resetting the old ledger. Unknown stops the new round
as before. No automatic retry/top-up/model change.

Pin the actual original checksum-valid ledger SHA256
`0743f051b0291623240dd4c10f8f0260f04b74ef1197a4279af13bbbfbcf3fc7`.
It contains exactly1 unknown/stopped entry, retained1310 micro-CNY. The new round
has a distinct immutable identity, max2 entries, ceiling998690 micro-CNY. Both
rounds therefore remain <=1000000 micro-CNY and <=3 attempts. Full history/token
proof, prices, output128, fixed endpoint and no-retry transport remain unchanged.

Keep the original ledger byte-identical and never migrate it. Create one fixed
follow-up sibling directory under the same stable private files parent, with its own ledger,
lock and crash marker. A root-level one-time marker must be durable before new
round provisioning; marker-present/missing-or-corrupt round data fails closed,
not recreation. A child without its marker is refused. The marker is not a UI or
IPC permission; only this reviewed trusted build can select this authorized round.

Every new-round reserve/handoff/success/stop/read acquires the original batch lock
before its own lock and validates the pinned original bytes, format and absence
of mutation-in-progress. Original mutation/corruption/loss refuses all new work.
The original lock also serializes cross-process cumulative accounting. Existing
legacy factories/format/tests retain their original behavior. No generic caller
parameters to choose a budget identity, prior charge, larger cap or new round.

The sibling is fixed-name, canonical/non-symlink, same owner as the original root
and exact0700; the original admission-root guard still allows only regular files.
Only liveChat's trusted Application opts into this fixed authorized round;
liveFixture keeps the existing default unless an explicit offline test selects
the new factory. Same original owner/callback/DB, dynamic budget identity/remaining
ceiling in authority facts. Rust's internal live batch allowlist must explicitly
accept only the legacy and this fixed new identity, preserve the actual approved
identity in usage, and validate it consistently with admission and receipts.
No public interface, callback, generated binding or search change.

Use a distinct fixed synthetic first message/codeCANARY-7391, not the original
unknown payload. Select its closed proof/verifier through the trusted installation
and apply it in owner reserve, context validation and response validation. Second
message still depends on the actual first answer; full history is required.

Architecture review found the old native controller retains RecoveryRequired
after its unknown, so a new ledger alone cannot authorize a new native run.
Proposed explicit new-round session: a fixed native root
`agent-service-authorized-followup-20261020`, beside the preserved original
`agent-service-root`. Only the trusted liveChat build selects it, after validating
the new round grant and pinned old ledger; no Intent/IPC/epoch/failure path input.
Same owner DB, callback and Rust Agent implementation; old native unknown stays
untouched. No controller RecoveryRequired exception or global Ready reset.
The new fixed root persists across processes; its own unknown retains the same
recovery/stop gates. This explicit session decision needs independent CLEAR and
device tests; it is not a generic directory switch or a retry mechanism.

Offline tests must reproduce the exact public old-ledger fixture (no secret),
check preserved SHA, old and new unknown independently stopped, new two attempts
and third refused, cumulative amount/counter, process/epoch reopen, missing marker
or lost/corrupt new data, changed old bytes and reservation/unknown crash handling.
Independent design/source review and targeted build/device checks precede the
authorized credential load and at most two new real ordinary UI Sends. Second
Send requires first accepted reply and exact actual history. No third new Send.

Independent design CLEAR accepted the fixed authorized session instead of any
RecoveryRequired exception. After a persistent new attempt, lstat/UID/mode/
canonical checks require outer root, native-agent-service-v1 and its0600 index.db
already exist; loss is never repaired by the native constructor. Process-global
retention and same owner/DB/callback are unchanged. A separate followupFixture
has no INTERNET permission, public synthetic prior evidence and code7391;
legacy liveFixture continues its original mode.

Independent review found and closed a concrete receipt defect: changing both
usage.batch and provider.budget_revision together could disguise one approved
batch as the other. A fixed batch-to-grant mapping now checks actual admission
against frozen authority before exchange, and receipt context must match frozen
source_binding, provider grant must match authority, and batch/grant must match.
Both directions of paired-field tampering were RED before the fix (completed
answer exposed) and rejected after it. Final Rust and architecture SOURCE APPROVE
replace earlier incomplete approval. No public/generated/search/controller change.

Fresh independent offline checks: budget19 groups (original11 retained), reference
renderer4 fixtures, Rust live-controller9 tests, HTTPS68 checks, diffcheck PASS.
Android followup test compilation/lint PASS56s,0 errors/15 warnings. Existing
Gradle journal corruption warnings remain; no shared cache deleted. Initial
Rust bare command failed macOS SQLite linking, and default parallel controller
tests hit the existing singleton Busy; correct sqlite flag and serial target
passed. A first new Rust fixture test lacked its parent directory; test setup
was corrected and rerun. These failed invocations are retained, not provider runs.
Exact-source native/APK/device gates remain required before real handover.

Official public documentation rechecked2026-10-20 10:32 +0800: deepseek-flash /
DeepSeek-V4.1-Flash-1017, peak CNY per million hit0.04/miss2/output8 unchanged;
thinking disabled and max_tokens128 still supported. Sources:
https://api-docs.deepseek.com/zh-cn/quick_start/pricing/
https://api-docs.deepseek.com/api/create-chat-completion/
No account/model/balance API or credentials were accessed for this check.
