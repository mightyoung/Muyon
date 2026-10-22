# Ledger — SCHEMA2-PLAN.md

Base90b7a35a49f4acb09ff73a2b088df4c1d1a037a6. Interfaces/plan commit
3a625b34ca6468bb9c1c9338b087ad43d9db04b6; native implementation as delegated.
Preflight: text mapping consumes fingerprint expanded tree; journal consumes private
PreparedEngineRequest + shared core grants. Neither may mint validation or run worker.
Ruling: continue the explicitly delegated approved plan without another permission
round-trip; only own task branch/source. Cost if wrong: parent can reject isolated patch.
Ruling: no safe object-pin prep hook exists in fixed a27; journal bytes remain bounded
SQL preparation only, not a fake FinishedBlob or pin. Cost: actual edited publication
stays Unsupported and needs cross-owner hook before integration.

Task1 complete: golden serializer API RED02 -> green03 (5vectors in2 tests); Python
ASCII canonical bytes/hash. Independent2308 Unicode sample comparison available.
Task2 complete: text mapping API RED05 -> green06 (6schema2+6oldprotocol tests).
04 additionally contained two test Value assignment compile errors, corrected in05.
Policy epoch has a targeted prior-source behavioral regression RED14 (exact90b7
module on exacta27core), then current green15. That replay proves legacy identity
invalidation; it is not presented as an earlier preimplementation policy test.
Task3 complete: journal API RED07 -> firstgreen08; independent quota finding actual
behaviorRED09 -> helpergreen10; edited private-byte disclosure actual behaviorRED12
-> fresh edit confirmationgreen13.11 was fixture grant-generation misuse, not product
behavior; kept raw. Expiry test in08 used wrong SQL column, corrected before10; then
split four named cases15. Negative mutation18 omits final effect check and all four
revoke/expiry/generation/epoch tests FAIL, establishing real tail-check sensitivity.
Task4 full core262passed,0failed,0warning17; workspace MSRV failure19 retained;
ownedfmt20exit0. Fresh independent final review complete: exact fullcore262/262 plus5 probes and2308 Unicode cases, no remaining blocker.
Task5: source and evidence commits recorded in SCHEMA2-HANDOFF.md; normal original-branch push only. No merge/delete/deploy; integration choice was already specified by parent.

Final: fixed shared quota — behaviorRED09 -> green10 and fullcore262.
Final: fixed expiry test column — corrected10/15; removed-tail mutation18 makes
all4 independent tail cases fail, then exact production fullcore262 is green.
Final: stricter unpublished bytes — behaviorRED12 -> green13/fullcore262.
No deferred minor finding. Fixed dependencies unchanged; source remains HOLD.
