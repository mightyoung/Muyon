> Latest durable COPY batch: see [DURABLE-REPORT.md](DURABLE-REPORT.md).
> Earlier contract-only results and limitations below are historical.

# DOC-06/08 offline transaction contract

Base: UI shell 3ecb544ad0a47ccc38fe830777f35588b92e8afc, verified remote unchanged.
Candidate verified: codex/muyon-android-refactor f4781e16ddf4e542b983fbd77f266a0071148255.
No AGENTS.md exists in this checkout or fixed UI tree. Read HANDOVER-LEADER,
ui-shell HANDOFF/NEXT-BATCH, REVIEW.md, contract.rs, business.rs and host_effect_intent.dart.
User's current request to retain raw logs supersedes historical REVIEW.md log exclusion.

Library research read in full: libfile_c94323014d388191ba1853e9aef8f532 (194 lines),
libfile_f74abbd878e081918ff0e1886325a7fd (185 lines). Only original neutral contract code;
no binary/decompiled/source-available vendor code copied. No engines/SDKs added.

1. Tests first: identity, preview without authority, exact confirmation, current host
   authority, copy-only candidate, validation evidence, CAS receipt, duplicate refusal,
   unknown original-intent recovery, cancellation and explicit rollback transaction.
2. Implement pure std module and typed lifecycle commands under document_edit/.
3. Run rustc path tests and negative mutation checks; attempt native project gate offline.
4. Independent non-author review, fix important findings, retain raw results and push only
   task/document-edit-transactions-20261022. Leader B alone integrates develop.

Adapter boundary: no document-core branch was advertised by remote at initial check.
Host facts are ordinary in-process observations, not grants and not model/wire inputs.
This unexported module neither executes effects nor authorizes any existing business API.
Source identity/revision/scope, live grant generation/epoch and exact binding must be
resolved by a future trusted document-core adapter, with durable intent claim, atomic
CAS/immutable output, and original-intent query. Trait integration is deferred until the
owner publishes an exact reviewed interface. No fake integration or JSON grant decoder.

Validation reports must explicitly cover reopened container, structure, semantics,
render comparison, unsupported-feature preservation, and formula status. Synthetic
fixtures test contract checks only; they do not demonstrate Office fidelity.

## Updated dependency boundary after publication

The document-core owner published interface 85daa64449c494eb005589ca71b164a48c470951
and final source ab9c381cc935be0cd52db5a8a455ce985bdba1db during this task.
The final implementation directly uses its DocumentRef, CapabilityMatrix,
DocumentOperation/CapabilityStatus and existing contract::Revision/AuthorityBinding;
no second document identity/revision/authority type remains. Earlier path-only logs
and reviewer hashes are historical iterations, not evidence for the final API.

Final verification uses an archive of that exact dependency plus only our two owned
source/test files in a temporary combination tree. lib.rs/documents/ in the working
branch remain untouched. verify-combination.sh reproduces this offline combination.
The bare UI-base branch requires the document-core dependency before its integration
test can compile; it does not pretend to include the core owner's exports.

HostFacts must come from trusted operation-specific host resolution. Permission
intersection and a Supported capability (or ReadOnly for read operations only) are
both required; Unknown/default/gated states deny. CurrentDocument/validate_read and
RevisionPrecondition do not implement durable write, intent claim or atomic CAS.
Commit validates a host-supplied durable original-intent receipt; it never publishes.
Without the future durable atomic gateway there is no real publication API.

After original-intent recovery under a new grant generation/epoch, subsequent effects
still cannot reuse the old confirmation. Cancel and uncertainty recording are local
state changes, do not disclose candidate bytes, and do not require a live write grant.
Read-only recovery still requires current active scope access and Inspect permission/
capability. Apply uncertainty and commit uncertainty are distinct recovery phases.
