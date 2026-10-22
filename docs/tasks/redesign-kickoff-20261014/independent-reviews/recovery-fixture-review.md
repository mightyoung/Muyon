# D03a recovery fixture independent review

Conclusion: **C0 for draft fixture-material intake only**. Fixed commit `55480f06490983a54e38908b043b06b4b02df451` on `task/leader-b-redesign-d03a-fixtures-20261014`, base `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`. Reviewer is not author `/root/redesign_d03a_contract`; no repository changes, commits, pushes, product execution or simulated recovery runner performed.

Fixed sources: P `01e56cc2d729dab70e1b1def05c3aa93b28f421a`, D `58fe9c62612d74a973614c41677e62a54332e6d6`, D03a contract `40f3cddb6e62baa2374bde288120d2385cb14c3f`, D01a delta `99c4d779bb5b94e3388637228f42869d6e81152d`, bc5b applicability clarification and original A00 directory. Reviewed immutable git blobs, not unfixed writer content.

## Scope, integrity and honesty

Exactly four added reserved paths: task registration, fixture README, SHA256SUMS and recovery-scenarios.json. No change to original design, contract, product, schema, CI, tests, old worktree or existing writer. Actual independent JSON checks confirmed 19 sequential D03A groups; 72 unique local case IDs (16 positive/56 negative), 144 complete store/scope/stream/seq cursor objects with decimal string seq; all cases not_run and actual/golden null; top-level runtime evidence null. Checked 21 immutable source references and each group’s references/acceptance mappings, both SHA256SUMS entries, all local Markdown links and `git diff --check bc5b 55480`: passed.

These structural results are **not 72 runtime passes**, new product DTO evidence, validated fault injection, Android load, M03 freeze or M12 implementation. The 52 primary acceptance cases remain unchanged/not_run and the 29 A00 classification subcases remain not_run. D03A-19 is explicitly later D03/D06/P3 boundary input, not widened first-slice implementation.

## Contract mapping and semantic checks

| Groups | Assessment |
| --- | --- |
| 01–02 | Full cursor comparison domain preserved; wrong store/scope/stream rejected even with larger seq. Restart preserves log identity/watermark; stream bootstrap does not rekey original operation |
| 03–04 | Snapshot state/cover and durable cursor atomic; slow stale snapshot cannot replace current state; equal watermark fork isolated; seven crash boundaries require old-or-new consistent commit; in-place two-transaction layout rejected; independent draft preserved |
| 05–06 | Duplicate zero extra apply/notification, same event identity/different payload quarantined, gap bounded repair. Authorized projection advance needs core proof; audit sequence/delta does not expose hidden event count. Permission narrowing clears affected projection before new snapshot |
| 07–08 | Invalid/expired/incomplete/cyclic/wrong-digest/schema candidates not activated. Known receipt retained under partial history; bounded budget with resync reason, authoritative terminal facts persisted first, no business replay. Tiny budget explicitly synthetic, not product default |
| 09–10 | Epoch fences display only; old real receipt hint requires current-connection identity/digest/ledger lookup, cannot be discarded solely for old epoch or create authority by itself. Revoked body stays hidden; historical effect revision and current object revision separate |
| 11–12 | PendingInput message/submission identity independent of projection; body persistence follows effective policy. No new retention defaults. Timeout queries original acceptance, absence remains delivery_unknown, IPC duplicate creates zero second message/intent/model turn |
| 13–15 | Same intent receipt/operation remains stable across Attempt/restart; changed binding conflicts without rekey. Credible new same-name intent writes once revision+1; key-only claim rejected. Cancel/navigation do not erase committed effect |
| 16–19 | Proven durable zero-dispatch distinguished from claim-only/possibly dispatched/notFound/unreadable. Unknown has zero autoreplay. Genuine “do again” binds user instruction, original unknown action/version, display/scope/action/normalized parameters/new intent and plan; seven untrusted origins rejected. New success leaves old unknown. Binding changes recheck plan. FullAllow pure risk zero extra confirmation; real scope/capability/business/CAS restrictions stay. Old backup prepared does not prove no later dispatch |

No blocking or required semantic correction identified in this fixed fixture draft. Generic truth labels such as `evidence_valid`, `trusted_issuer_fixture`, `all_hard_prerequisites_valid` are explicitly controlled input requirements, not renderer authority or production signatures. Future actual runner must issue or verify evidence through real trusted host/core entry, exercise fault boundaries, observe durable store/receipt results and reject forged proofs; copying expected values into actual would not constitute validation.

M03 field/schema/enum/digest/encoding/error/threshold decisions and actual trusted fixture mapping remain pending. No claim of runtime security or platform equivalence follows from this C0. Supporting machine proof: recovery-proof.json outside Git. Raw inspection output outside Git, no user/model/credential data materialized.
