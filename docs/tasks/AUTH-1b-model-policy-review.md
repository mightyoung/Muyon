# AUTH-1b C1/C2 fixed-source acceptance and integration

Leader B approved source `7c1dd63000b81043f0f51774175cf9ef7bc7e850` for a normal develop merge after non-author review. C1 `d23127824e4218ac58794a98a0998a7ed1179048` and the original C2 `b423064b4ee6c4db1fd640b5fe5e08f039d0598d` keep their original evidence; b423 had a SHOULD and was not accepted before repair.

## Scope and acceptance

The task adds category policy and actual host-owned model wire authorization. It covers full profile/endpoint identity, current trusted configuration, local/own-device mode_auto with nullable grant ID, actual grants and atomic ledger/use/audit, independent local review, main requests, summaries, compatibility retries and disk restoration. Historical migration facts and data are retained. No UI, main or release changes are authorized here.

Non-author fixed-source repair review found no new BLOCK/SHOULD and closed the original review/revoke/credential SHOULD. At exact 7c, independent strict analysis passed in 69.3s and 126 focused tests passed in 46s, including the original persisted-revoke probe and another actual PersonalAgent model send exhausting the final grant. The repair reviewer did not repeat the full suite. Original b423 independent strict/full1133 with 3 existing skips remains historical evidence, not repaired-source acceptance.

Leader B separately checked these logs, source and exact remote identity, and reran 16 focused tests from an exact git archive in 1:31. Author repair evidence is separate: strict18.9s, full1136 passed/3 existing skips in6:28, 16 valid mutants detected with byte-identical source restoration. The exact task CI [37778023749](https://github.com/mightyoung/Muyon/actions/runs/37778023749) completed successfully at 7c. Raw reports, probes and logs remain under /tmp and are not committed.

## Integration

Base: latest fetched develop `dbc19fbe6020dea761539353feecea82f4de654d`. Normal no-ff merge of approved 7c had no conflicts and preserves concurrent JR1/doctor and handover changes. Integration verification results are recorded below after completion.

## Limits

Evidence uses actual Host, SQLite, loopback protocol fixtures and real Inquiry/Research stores; scripted model responses do not prove real-provider behavior. UI/profile settings entry, other modules' business loops, real cloud models and physical devices remain deferred. Revocation subscriptions are scoped to a shared ManagedDatabase owner, not cross-process/multiple-connection guarantees; bytes already sent cannot be withdrawn. Existing terminal-map cleanup WATCH remains deferred. This acceptance does not declare all AUTH or product work complete.

## Integration gate result and baseline blocker

Whole-repository strict analysis: no issues (201.9s). All seven package analyses passed. Doctor: all23 scenarios passed. Four Laya script groups passed. `scripts/verify.sh` exited1: module_api29, muyon_ui225, prototype40, research216, supplier_core482/3 skips and host1136/3 skips passed; inquiry281/1 skip/46 screenshot failures. This is not a full green gate.

Standalone desktop settings failed at0.57%,5830px both in this merge and independent untouched latest develop0c9ee296770182155b1b700bbf6576f2f5cc184d. Setting FLUTTER_ROOT explicitly did not change the result. Actual PNG SHA256 in both trees: bf18dc615cd18ae20cb211e40ff25f93541c2470dc2f4d48deba612900234411. Inquiry package, UI package and dependency lockfile match develop exactly. This demonstrates the selected failure already exists on the baseline; it does not claim every one of the46 failures was individually rerun.

Raw evidence remains /tmp/auth-c2-integration-verify.log, /tmp/auth-c2-integration-screenshot-diagnostic.log, /tmp/auth-c2-integration-screenshot-font-env.log and /tmp/auth-c2-golden-develop-control.log. No golden update or relaxed assertion. Integration is saved for review; develop publication remains blocked until leader explicitly resolves the baseline gate. The newer0c9ee29 document-only update is preserved by normal merge, not overwritten.

## User-accepted finite baseline exception (2026-10-08)

Subsequent full Inquiry comparison against exact develop4573adb73f32526bc3f3bab8125db923e474f890 found the same281 passed/1 skip/46 failures: canonical cases, image dimensions/different-pixel counts and all184 PNG SHA256 values identical; added/removed/changed0. Exact integrationffe6be31a8a4cb516f8bcc5331a3065cbc142dcd LinuxCI37786931707 completed/success, analyze7/7 and test7/7. No source, golden, skip or assertion changes.

The user explicitly accepted this finite baseline exception and authorized develop publication. This supersedes the publication blocker above, without relabeling the failed Mac gate as green or claiming the unknown root cause resolved. [Verification memo](VERIFICATION-MEMO.md) preserves the decision, evidence summary and mandatory later regression checks. Raw logs/matrices remain outside Git.

发布完成：正常快进4573adb→00dbd6cf722ddd4b5f7e8c65ec378ee4150fada9，包含获批ffe6be31及四份文档备忘录；[精确发布CI37792414130](https://github.com/mightyoung/Muyon/actions/runs/37792414130) completed/success。原Mac失败未重写为通过，基线例外不得自动延续，main/release未动。
