# Reader selection-consent independent review

Reviewer `/root/review_shell`, 2026-10-22 UTC. Reviewed final uncommitted ReaderSurfaceFence/Checks increment against `c0c2dc994df099c36c83813adf8410dac999d943` (requested baseline c0c2dc994df099c36c83813adf8410dac999d943). Final production SHA256 `0e20ae687f2471d5d16dce07e75f7946da03493ece5f6bbf69ce27e182a7da42`, checks `45d883b10dfdeea32d9ff57a40544eed8d532997f65c8eda5e5f2fda983775b0`. All inputs, command, captured stdout and exit are in [reader-consent-independent.log](evidence/reader-consent-independent.log). Hashes were identical before/after the independent run. This replaces the intermediate review before the authoritative invalidation hook was added.

No production/other-owner files were changed by this reviewer; only this report and its log were written. No commit was created.

## Independent result

Actual runner compiled real DocumentReaderModels, ReaderSurfaceFence and Checks with Kotlin2.2.20 `-Werror` JVM17. Exit0 PASS; `git diff --check` PASS. Synthetic Host/resource fixtures only; no real Host, policy, Service/FFI, file, model/search or paid request.

Executed assertions cover exact one-use readonly selection intent, failed cross-request consumption, distinct IDs for genuine choices, no fresh consent on lifecycle resume and repeated new intent IDs failing to overcome a synthetic authoritative denial. Existing A/B/A, selection-before-open, frame-only handoff, stale pre-Host zero calls, exact original-selection stop, late/duplicate resource closure, owner-thread callback queue, unknown cleanup hold and no auto-resume checks remain in the suite.

Final added invalidation assertions cover: current displayed selection loses output and closes its exact resource after Host invalidation; old A invalidation cannot stop current B; repeated old A invalidation cannot stop a renewed A choice, including when it arrives before renewed Opened.

## Static findings and resolution

A genuine explicit choice of a current-project registered local document can express this one readonly intent under the user's authorization. The intent object binds the exact request by reference and consumes once; its UUID is not a native grant, provenance, account ACL, principal or a way to reset document revocation. The future Host still must validate registration, canonical source/revision/digest, scope and live authoritative revocation before opening. Internal construction is a local ordering mechanism, not an isolation boundary against other trusted app code.

Finite ReaderChainCleanup reasons stop this reading chain/child grants. Lifecycle stop does not permanently revoke document permission. A later genuine click can create a new readonly intent, but Host denial remains authoritative; no write/export/execution authority is added. Frame resource handoff remains distinct from ending the selected document chain. Existing resource cleanup holds and exactly-once close wrappers remain intact.

The review initially found no independent Host-to-surface invalidation entry after Opened. This is now closed in the final increment: acceptSelection receives a dedicated invalidated callback capturing the original selection event; postOwner marshals it, and selectionEvent identity must still match before advancing HOST_INVALIDATED. Output/fence is cleared before exact chain/resource cleanup. Old/duplicate invalidations cannot target a different selection, and invalidation does not alter the authoritative document ACL. The one-open receive callback is not repurposed as revocation.

No outstanding Important issue was identified in this bounded final source review.

## Remaining gates

Production Activity construction still supplies host=null. Canonical catalog returns no records with explicit unavailable explanation. It does not fabricate a document row, policy decision, successful read or continuous authorization. The new callback is only an interface seam until the actual trusted Host/policy/FFI coordinator exists.

Pure checks do not run ActivityReaderSurface, Android lifecycle/Handler, Compose, native freshness, TTL renewal or real PFD/bitmap revocation. Existing Android AGP failure and lifecycle instrumentation NOT_RUN remain. Actual policy registration, source checks and authoritative invalidation delivery must be tested with the eventual concrete Host; synthetic denial tests do not establish that production bridge.
