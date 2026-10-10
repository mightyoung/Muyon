# F5b slice 3b: 33 component adapters

Status proposed integration. Native Codex implementation; capture/catalog/adapter changes after b0bb717 are not covered by the completed real Claude limited source review. No production host catalog switch or develop merge.

One library-2 adapter table covers all 33 catalog names. The twelve existing components reuse the original renderer/controller; the 21 library additions construct their real widgets from validated host projections. Collection cells resolve through the existing session; selections read the separate selection projection and never become scalar resolve values. All callbacks use the build-frozen UiRenderCapture. Library-1 still falls back for the whole surface.

Choice uses stable IDs and host multiplicity; Checklist freezes row order for index-to-ID conversion. Tabs and Disclosure use controlled view values. NumberStepper/Slider use host finite-number bounds/step, preserving fractional values. Decimal slider division validation uses the existing UiNumberEdit grid precision of 1e-9 to absorb binary representation error (0.3/0.1); no domain amount or quantity is converted/truncated. Nullable numeric/bool values display unset without fabricating zero. Date bounds are mandatory host metadata; an unset date picker clamps its initial browsing date within supplied bounds and creates no draft until a selection. FileCard filenames require string host facts. Invalid decimal Field text restores the accepted display; valid String decimals retain precision.

Chart geometry omits missing points and retains a same-source table with the exact canonical decimal string. Fact/computed state, unit and source IDs remain visible, including conflict/notDisclosed; no best mark or verified state is inferred. CompareTable marks only nonverified evidence as unverified. Trusted row navigation is an optional local onOpenObject port, resolved by stable ID against the accepted host registry/object/source digest; it never routes through the business event sink. The host still owns final scope/lease/navigation checks after awaits (F4c H3); this fixture port does not prove those checks. Form read-only disables its subtree through the existing MuyonForm behavior.

## Evidence

- Actual renderer RED b8b0702: a valid library-2 plan fell back; no target adapter widget rendered.
- Additional actual catalog RED: numeric FileCard admitted incorrectly; 0.3 range / 0.1 slider step rejected incorrectly. Both now pass; wrong/off-grid/oversized divisions remain rejected.
- All 33 real schemas compile via aiui-stream/2 and shared end validation, and each produces an actual opted-in surface target without unavailable-component fallback.
- Real Widget callbacks for Choice, Checklist, NumberStepper, Slider, Toggle and DateField reach the existing typed session; decimal 2.5 stays 2.5, item IDs remain separate from scalar overrides. Tabs/Disclosure update view values with zero draft increment. Unknown Tabs child ID is rejected before mutation.
- Saved old row callback invoked after acceptPlan but before rebuild causes zero navigation and zero business sink; current callback opens the exact trusted ObjectRef and leaves draft/detailNode unchanged.
- Mutation removing Field rejected-text restoration produces a real failure (expected 1.5, actual oops); source restored byte-for-byte, then complete tests rerun.
- Final complete module API: 159 passed. Final complete muyon_ui: 497 passed. UI strict flutter_lints: zero diagnostics; API changed files: zero diagnostics. The two previously reported owner-external infos (context.dart null-aware element and PR21 core test function declaration) remain; temporary strict configs were removed, not committed.

## Handoff

The next authorized slice consumes PR30 ac0a0efa921236a765d7e9c56f3e2bf8a22acd0f in the shared state/surface owner branch and targets PR18 same-session Widget RED. Publication/rebase, dispatch admission and mounted identity are not claimed by this component slice. Workspace version-2 recovery/CAS and final host navigation scope/lease admission remain separate owned tasks. Structural reference metadata 64KiB clarification remains explicitly pending parent review.
