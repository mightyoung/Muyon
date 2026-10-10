# F5c prepared session rebase and H1b handoff

Status: proposed integration; independently tested session preparation implemented. Parent remains sole technical adopter and integrator. No production catalog switch or develop merge.

## Fixed dependencies and authorship

- Component adapter baseline: `505d0e806ac77b8295197de082351dd5ba68c26e`, draft PR28. Its two GitHub Actions runs `38027565858` and `38027562542` passed. Those results do not cover this later patch.
- PR30 pinned source: `ac0a0efa921236a765d7e9c56f3e2bf8a22acd0f`. Only its three coordinator/test/document commits were cherry-picked as `f2a0718`, `85d1510`, `a663ec7`; its develop ancestry was not merged. `publication.dart` remains byte-identical to that source. The public barrel exports it; two now-redundant direct test imports were removed, without altering the 16 coordinator assertions.
- Native implementation follows the parent's explicit authorization after Claude quota exhaustion. Real Claude review of earlier `b0bb717` is recorded in `AIUI-5-F5b-claude-cross-review-b0bb717.md`; it does not review later capture, catalog, adapters, or prepared rebase.
- Original workspace remains untouched. Raw invocation/test logs remain outside Git in `/tmp/aiui-f5b-logs`.

## Implemented boundary

`UiSessionState.prepareRebase(ValidatedUiPlan)` creates an owner-bound prepared capability after validating all layers. Same catalog identity, surface, intent ID and snapshot ID are required; snapshot and plan revisions must advance. It prepares extracted values, scalar overrides, view state, item-ID selection overrides and source digests before publication. A rejected previous manual value remains in immutable `readableDraft` with `unreadableReasons`, while only valid values enter active layers. There is no silent filtering of invalid selected IDs; changing the referenced collection rejects the previous selection even when an ID happens to coincide. Unbound view keys cannot become business draft inputs.

`canCommitPreparedRebase` checks originating session, original accepted plan and local mutation epoch. Accepted edits, adoption, source changes, workspace restore and plan advance invalidate old preparations. `commitPreparedRebase(prepared, accepted: publisherCapability)` additionally requires identical raw plan/snapshot/intent/catalog references. Its commit consists only of local assignments and stale-read-cache reset; no host predicate, notification or await runs there. The same session object survives. Explicit adoption or a valid edit can clear a retained rejected value. These APIs are preparation/install primitives, not a cross-object publication transaction.

Nine session tests cover preservation/adoption, rejected scalar and removed selection retention, view/source epoch fences, throwing predicate isolation, exact publisher capability, unbound view/business collision, collection identity change, stale source cache reset and foreign-session rejection. Their computed values are prebuilt candidates; they do not claim actual F3a formula execution.

The accompanying UI changes verify actual widget types beneath all 33 rendered component keys, and show an unset nullable Disclosure as unset rather than inventing `initiallyExpanded`. Slider grid validation rounds only the division count within the existing 1e-9 tolerance, then checks the 1..10000 bounds; domain values are neither rounded nor truncated. Added floating-point boundary cases failed behaviorally against the old validator (`slider_step_unrepresentable`) and pass after restoration of the fix.

## Verification

Final source-tree checks with existing cached Flutter 3.47.5/Dart 3.13.4, `--no-pub`, no SDK or dependency download:

- API package: **184 passed** (including 16 independent coordinator and 9 session rebase tests).
- UI package: **498 passed**.
- Strict `flutter_lints` analysis: own changed source/tests and entire UI package have no diagnostics. Two existing owner-external infos remain: `context.dart:33` (`use_null_aware_elements`, PR22 owner) and `ui_recomputation_contract_test.dart:246` (`prefer_function_declarations_over_variables`, PR21 owner). Temporary analysis configs are removed before commit.
- `git diff --check` passes. Candidate core patch passes `git apply --check` only; it is not applied, compiled or behaviorally tested.

Logs: `rebase-final-api.log`, `rebase-final-ui.log`, `rebase-final-analyze.log`, `slider-boundary-real-red.log` in the external task log directory. New-head remote CI must be evaluated separately.

## Concrete remaining interface and ownership decisions

1. **Core owner (`publication.dart`)**: review `AIUI-5-F5c-H1b-core-owner-candidate.patch`. It proposes same-snapshot validated plan adoption and a plain mutation fence checked after the final token probe. Current PR30 has neither: legacy `acceptPlan` can otherwise diverge from coordinator current, and local view/source mutations can invalidate prepared layers without changing the business draft token. Candidate names and behavior remain proposed. Preserve pending draft floor, downgrade diagnostics and latest-request/disposal isolation.
2. **This task's assigned shared-state/surface owner**: once that core boundary is adopted, install prepared session layers with the actual published capability in one synchronous, no-callback section; notify only afterward. Keep one authoritative current plan, retain pending locks/receipts, route admission through the coordinator, and preserve mounted field controllers/focus on same-controller snapshot publication. None of this live integration is implemented here. `state.dart` and `surface.dart` should have one writer; parent may explicitly reassign ownership from the submitted head before further writes.
3. **F3b caller owner**: PR18 pinned `758fe718d66a1d4591d73e534c83b19332850e4b` has two Widget REDs whose controllers receive no recompute port. Its apps-owned adapter can evaluate the real registry but the UI package cannot discover that registry. Proposed constructor ports are optional `UiRecomputePort? recomputePort` and `UiPublishTokenProbe? publishTokenProbe`; F3b must inject its real adapter/probe into the mounted test host after interface adoption. Preserve the 30/40 assertions. No fake evaluator, detached registry result or second runtime is an acceptable GREEN. Apps adapter/acceptance files are not edited by this task.
4. **Separate follow-ups**: workspace v2/CAS restore and F4c navigation scope/lease checks remain their assigned owners. Existing local trusted ObjectRef navigation is not claimed as final host authorization.

Until (1) and (3) are technically assigned/adopted, H1 live publication/admission and the PR18 same-session two Widget REDs remain open. No per-item user adoption is inferred from this report.
