# Batch ABA and actual gateway tail: fixed source, validation pending

Final real source: `a961bb58c08ce77b559ce0d021d2ed50a857bb9e`.
Branch: `task/document-source-invalidation-applied-20261022`.
Baseline remains explicit B `662aeec6d6462cabfcc317e855ae23797dd88d51`.
No gateway, Artifacts/Evidence, lib.rs, harness or B source branch was changed.

## Fixed interface for the original gateway owner

See `GATEWAY-PUBLICATION-TAIL-INTERFACE.md` (signatures unchanged).
The API first landed in `9a357f27c972ef2a9f7c9a0063be3d7d4a66e301`; use final a961 source for the complete generation freeze boundary.

The real COPY gateway currently calls the legacy clone, then updates its committed receipt, then only checks grant. That receipt UPDATE can trigger notification deletion/pre-ACK after clone's local tail. **The unchanged gateway remains HOLD.** Core-only clone tests do not verify that actual receipt path.

Required original gateway owner change: call `document_clone_with_postcondition_in_transaction` and retain the opaque token from its returned tuple. After the REAL receipt/journal writes, response load and original grant/expiry check, call `document_publication_postcondition_in_transaction(&tx, token)`, propagate errors, and COMMIT with no business write after that call. Do not reconstruct a token from receipt JSON or caller fields. Receipt owner must still verify its own receipt/state facts. New additive publish hook offers the same token seam without enabling any edited-candidate publication.

The token is crate-private, fields private, no Clone/serde/constructor. It borrows the EXACT Transaction object and checks pointer plus BusinessStore connection. It retains core-created exact metadata/reference/upload conversion and the complete source postcondition. The consuming tail is read-only and verifies source routing/tombstone preimages, actual invalidations, queue generations/pending, blob ledger and precise head/metadata. This is an effect receipt, not authorization or validation evidence.

## ABA root cause and complete freeze boundary

Independent evidence `8caf013406408c9cb15fc7f854cc7afdf1c0ff99` actually ran e3fa: original three trigger REDs became GREEN, but the new same-batch ABA probe was RED: second revoke reused object-z generation1 and stale ACK1 returned1, deleting the new event. Its copied report is `PRIOR-E3FA-ABA-RUST-VERIFICATION.md`; original logs and source hashes remain at that immutable evidence commit. Its library182 and other targeted counts do NOT apply to the new source or to full core. Its three source-inclusion harness compilation failures, four-file fmt failure and workspace anyhow1.0.104 offline failure remain open historical records; no harness was deleted, disabled or modified here.

A first repair froze before outbox writes, but independent static review found source/binding UPDATE triggers could delete tombstones even earlier. a961 therefore prepares the complete related routing preimage BEFORE the original blob/head/grant writes, not merely before outbox writes. Grant replacement prepares old and new documents together before UPSERT. Prepare reads only project/document source routing keys (including inactive routes), pages256, bounds IDs128, and freezes their queue generation/pending/absence. It never decodes source authority or decides invalidity.

After original mutation, finish checks the preimage, calls the REAL owner invalidation hook for every prepared document, checks the entire preimage again, derives every next generation from the ORIGINAL frozen state, and verifies each target before its queue write. It then checks the complete final batch, including unchanged tombstones for unaffected related routes and source/binding route existence. A deleted/changed old tombstone causes rollback rather than generation reuse. Unknown returned routes or duplicate invalidations reject. BTreeMap/Set avoid affected-by-route quadratic lookup. The complete expected state is retained in the gateway token so later receipt writes cannot escape the same checks.

No owner permission logic was copied; actual source authority/invalidity still comes only from the owner's real hook. Preparation only reads metadata. Namespace absent vs installed/corrupt distinction remains. A token does not allow historic reads, new grants, paths, engines, files or network operations. Source owner hook and preimage retain all related objects in memory: 256-row pages do not establish a total memory/disk quota or performance guarantee.

## Tests, evidence and remaining gates

There are24 authored source-notification tests. New same-batch ABA regression was committed BEFORE its repair at `b178eaa3b171ccc254fe86137b7bd8bf5b340845`; that source can be used for real RED reproduction without absent new API methods. New early grant/source/binding trigger regression was committed before the final repair at `338ae89a45456204390f4a71c00c738930ba3f73`. These are test-first SOURCE points, not local runtime RED claims (cargo127).

Core-only new token tests check a later write deleting/pre-acking notifications, reactivating source, deleting blob reference, restoring old head; foreign transaction rejection; exact transaction success. They explicitly do not claim the real gateway receipt path ran. Existing original three probe logic and prior20 tests are not removed or weakened. The one foreign-transaction test now calls prepare because the superseded single-phase private invalidation helper was replaced.

Final separate read-only review accepted exact a961: preparation is before all original writes, old/new are combined, postcondition covers affected/unaffected preimages, opaque lifetimes/private fields/pointer checks and BTree inference appear correct. No new static blocker. Review does not establish compile/GREEN.

`batch-tail-source-manifest.json` pins the final five changed core source/test files, root lib and gateway unchanged. `batch-tail-verification.log` preserves actual argv and outcome at a961: focused24, full core, workspace, strictClippy and five-path scoped rustfmt all **NOT_RUN127** (accessible cargo/rustfmt absent). No reattempt of denied /root tool locator occurred. Source-only `git diff --check BASE a961 -- crates/muyon-core/src` exits0. Full diff check exits2 because two preserved original raw logs have final blank lines; this is recorded, not silently normalized. Rustfmt is not claimed passed.

Required next validation: run the original independent ABA probe unchanged at a961 and prove RED-to-GREEN; run original three probes unchanged, authored24 and related actual library/Reader/presentation targets; B wires real harness modules in its own isolated combination and tests full core; preserve offline/fmt failures until actually resolved. Original gateway owner must reproduce its REAL receipt-trigger RED and run GREEN after consuming the new token. Host/Runtime poll/deliver/ack remains separate and not integrated. No B release, product completion, actual notification or deployment is claimed.
