# Gateway publication tail contract (source implementation follows)

Dependency: applied source branch based on B662aeec6; current prior source e3fa0ee7. Existing gateway remains HOLD until its original owner consumes this additive API and actual receipt-trigger probes pass. Core owner does NOT edit gateway.rs.

Exact crate-private additions on BusinessStore:

```rust
fn document_clone_with_postcondition_in_transaction<'tx, 'db>(
    &self, tx: &'tx Transaction<'db>, base: &DocumentRef,
    title: &str, expected_blob: &BlobRef,
) -> Result<(DocumentMetadata, DocumentPublicationPostcondition<'tx, 'db>)>;
fn document_publish_with_postcondition_in_transaction<'tx, 'db>(
    &self, tx: &'tx Transaction<'db>, base: &DocumentRef,
    title: &str, format: DocumentFormat, finished: &FinishedBlob,
) -> Result<(DocumentMetadata, DocumentPublicationPostcondition<'tx, 'db>)>;
fn document_publication_postcondition_in_transaction(
    &self, tx: &Transaction<'_>, postcondition: DocumentPublicationPostcondition<'_, '_>,
) -> Result<()>;
```

Opaque type path: `crate::documents::storage::DocumentPublicationPostcondition`. All fields private; no public constructor, Clone, Deserialize or Serialize. Only a successful real core publication creates it. It borrows the exact Transaction object, retains the exact published metadata/blob reference/upload conversion, original source notification generation receipts and namespace marker state. Tail compares the exact Transaction pointer AND BusinessStore connection, and consumes the token. No arbitrary serialized IDs/paths/generation vector can construct it. The token is an effect postcondition, NOT authorization or validator evidence.

Gateway must replace its current clone call with the tuple-returning additive call, retain the original opaque token, perform its real receipt UPDATE and any other journal writes, build its response, retain the original document_grant_in_transaction authority/expiry check, then consume the token with the final publication tail immediately before COMMIT. Propagate any error so the entire original transaction rolls back. No business write after the final tail. Affected source/binding inactivity, every precise notification generation/pending=1, exact head/metadata and blob publication ledger are rechecked after receipt triggers. This does not replace receipt owner checking its own exact state/digest/receipt.

Legacy clone/publish signatures remain compatible for existing compile paths, checking immediately after their OWN writes. Their returned metadata alone cannot prove later receipt writes safe. Existing publish_clone gateway is therefore NOT closed merely because core's direct clone tests pass. Actual gateway owner must reproduce receipt-trigger deletion/pre-ack RED and independently run GREEN on its integrated new source. Core-only late-write probes test the token seam and are not counted as gateway receipt-path tests.

Outbox generation fix is a separate source change: freeze all affected target generation/pending states before any outbox row write, derive next generations only from that frozen batch, compare each target against its original frozen state before writing, and verify the complete expected batch after all writes. Cross-row tombstone deletion must reject/rollback rather than reset generation1. Existing source hook returns all affected rows in memory; total mutation memory/disk limits are not newly claimed.
