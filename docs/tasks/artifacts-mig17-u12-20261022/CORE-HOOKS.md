> Historical first-batch record for 4eec6d16. Current continuation and fulfilled historical-hook integration: [WORKFLOW-REPORT.md](WORKFLOW-REPORT.md). Original evidence below is preserved.

# Core owner integration request

Required now: add `pub mod artifacts;` in core lib.rs; this branch never edits it.
All existing storage work uses fixed f4a8e8d hooks, not a speculative trait.

Required to unblock historical recovery: a concrete core-owned hook, e.g.

```rust
pub(crate) fn document_history_access_in_transaction(
    &self,
    tx: &Transaction<'_>,
    current: &DocumentAccess,
    historical: &DocumentRef,
    required: &[DocumentOperation],
) -> Result<DocumentMetadata, ContractError>
```

The core owner must settle policy and provide actual persisted authorization of
the historical target under live host identity/membership/project policy. Checking
`current.revision >= historical.revision` is insufficient. Existing grants bind
an exact DocumentRef. Publication-tail document_grant_in_transaction explicitly
does not authorize old revision reads, so artifacts cannot repurpose it.

The hook must validate transaction ownership, live project, exact same scope and
document identity, currently effective grant/epoch/generation/expiry, applicable
historical-read permission and immutable canonical history metadata. It must
reject revocation, missing history, mismatched target and current policy denial.
Source revision reads need the same hook; no implicit latest-source replacement.
No public bool/token/empty trait is proposed as a substitute.

Until supplied, artifact_authorize_record rejects changed output/source DocumentRef
with RevisionConflict. Historical rows remain durable. Restart recovery works for
exact still-authorized revisions. A page containing inaccessible historical
content fails atomically; callers must not display a success or substitute latest
content. History reading after output/source changes remains HOLD.

Byte delivery remains host-owned and must validate historical permission at use;
returning metadata is not a reader lease. No engine, render or edit capability is
made supported by this catalog.
