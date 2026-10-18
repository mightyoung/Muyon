# B independent read-only review

Reviewed source: clean `d25a407830ef624802583983c0be2414bbd59dc4`, tree `829f0d3d02bd5f8cf5f57ddef27f7fa4be3341db`. This report is scoped source/evidence review, not product integration acceptance.

## Source and contract preservation

- Merge `b0d5b849` preserves product2f and HTTP8e ancestry. Core/plugin/host runtime crate trees have zero diff from exact HTTP `8e0f6b1d`; the candidate adds product-side checks/mapper changes and checker commit only. No A verification or uncommitted WIP is present.
- Independently checked all 228 files in `b/source-fixture-sha256.txt`: zero mismatches. Additive inventory retains prior cases and explicitly names Core115/plugin22/host59 cases, rather than accepting counts alone.
- Native inverse script and fixture are byte-identical to product2f. Recorded exact-source native3 evidence contains three green baselines and three precise killed mutants. HTTP7 summary records all seven exact baseline/mutant pairs accepted.
- External combined runner changes preserve repository runners. Legacy adapter changes only source location and the equivalent stale-usage mutation anchor. Source-line/semantic audit below supplements the inherited broad legacy predicate.

## Legacy17 precise evidence

Independently read all 16 exact Rust baseline/mutant log pairs in `b/legacy17-exact/`. All 32 raw SHA256 values match the summary. Each mutant has the intended exact test identity, panic source line and semantic assertion from the unchanged shipping test source. Exit101, one exact failed test, intended semantic needles and natural owned cleanup are required by the audit; baseline exits are zero. Generic kernel `assertion` needles in the first runner are superseded by `legacy_assertion_audit.py` exact line and expression checks.

Independently re-evaluated the audit functions without invoking their writing main: 16 positives accepted and all 144 negative controls rejected. Negative controls include wrong exit, timeout, forced cleanup, remaining children, compilation failure, wrong source location, wrong target and removed semantic assertion.

Physical seventeenth raw log actually contains `RUST_WIRE_ARGS_ACK_OBSERVED`, the intended exact test, `AssertionError: 1 != 0 : PRETERMINAL_PHYSICAL_EFFECT`, and `FAILED (failures=1)`. Its raw SHA256 is `6c134d24885753100c2e9c61844039b21679b847e81c0d696df2dc6b342d45b4`.

The broad runner's earlier `wire_container_depth` KILLED label is rejected: its unrelated PID-file failure did not establish the intended depth oracle. The separate precise depth rerun is the evidence used here. No unrelated timing failure is counted as a semantic kill.

## Remaining acceptance and preservation gaps

1. First core Rust run failed `silent_and_eof_hanging_children_are_killed_and_reaped` with PID-file ENOENT; its original log and INVALID verdict remain. A second default-parallel Rust run passed115, but its `wire_process` gate remains INVALID/exit1 after an escaped-pair byte1 time-budget failure. Core full is therefore NOT PASSED; successful later execution must be separate evidence, not erase these failures. Root cause has not been established by this review.
2. Initial `combined-runner-provenance.json` had stale hashes for `combined_full.sh` and `combined_full.py`. RESOLVED: final `b/final-runner-provenance.json` seals all nine runner/guard/audit scripts; this reviewer independently checked every hash and all nine match. Initial provenance is retained as historical evidence.
3. Initial `b/legacy17-semantic-audit.json` was overwritten by orchestration metadata using the same path. RESOLVED: owner preserved initial metadata separately, restored the semantic result with 16 precise entries, physical17 and 144 negative controls, and used `legacy17-semantic-audit-run.json` for execution metadata. This reviewer read the corrected semantic result and independently reproduced the 144 checks without running mutation commands.
4. A/package evidence and a final complete core full rerun are outside the completed review here. No Android/device acceptance or remote dedicated CI claim is inferred.

Outcome: scoped PASS for HTTP source preservation, legacy17 precise semantic evidence and final runner sealing. Full integration gate remains OPEN pending complete core full execution and outstanding A/package evidence. All owner files were read-only; only this report was written.

## Incremental seal and raw-integrity review

The current final runner seal now covers11 scripts, including `recover_inventory.py` and `recover_physical.py`; this reviewer independently checked all11 hashes, all match. Prior nine-script/pre-recovery and pre-raw-integrity seals are retained. Recovery inventory re-enumerates unchanged source test names against the additive contract; physical helper extracts the original seventeenth inverse section unchanged rather than using the old broad classifier.

Updated semantic audit now verifies baseline and mutant raw hashes, reads actual physical ACK/assertion/build logs and records their hashes. This reviewer independently loaded its pure acceptance functions without invoking the writing main: all16 exact mutant records still pass. Both physical raw/build file hashes independently match the corrected semantic result. This strengthens preservation and does not imply a new mutation execution.

Core full final rerun remains pending. A/package scoped review is in `A-FINAL-REVIEW.md`; A's ordinary assembly is still running and device/runtime evidence remains NOT_RUN.

## Final completed core full review and stop

Independently checked `final-core-start.json` against current final provenance and all11 actual runner bytes: every hash matches the pre-run seal. Exact source/tree are d25a4078/829f0d3d; RUST_TEST_THREADS is unset. No original test-budget or physical-runner source relaxation was introduced.

Actual `core-full-final.json` records exit0 after106.92642879486084 seconds; the actual complete log SHA256 matches `10751eb36483489099ecbecf60093e77fa0c6c6fb872b6f76b2a889215736cd3`. All six final verdicts accept: Core115, physical process26, wire process18, harness6, wire harness7, and legacy17. The final script also runs the exact semantic audit, whose actual output is `True 144`.

The final physical seventeenth has a new actual compiled execution with ACK and the exact `AssertionError: 1 != 0 : PRETERMINAL_PHYSICAL_EFFECT`, exit1 and one expected failure. It is not inferred solely from the broad KILLED label. The16 precise baseline/mutant results remain the separately reviewed exact semantic evidence; the final broad legacy batch is not reinterpreted as16 newly precise target runs. Current semantic audit's actual physical raw/build hashes still match.

This closes the final core full execution gap. The historical PID-file ENOENT and escaped-pair budget failures remain preserved; this later pass does not establish their root cause. Stock repository gate remains unadapted for the additive combined inventory; success here uses the explicitly reviewed external combined runner, not a claimed stock-gate pass. No combined-source Android/package gate and no dedicated remote CI were run. A's completed ordinary assembly remains exact2f evidence only.

Final reviewed outcome: scoped PASS for B source preservation, additive contracts, native3/HTTP7, legacy17 precise supplement and completed default-parallel core full. Owner's remaining source/binary-integrity/OUTCOME/verification-commit sealing is not independently claimed complete by this report. This reviewer now stops; no further tests or writes are performed.
