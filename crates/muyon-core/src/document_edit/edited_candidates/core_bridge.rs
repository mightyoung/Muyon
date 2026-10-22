//! Original-intent invocation claim plus read-only observation of the real core
//! private object/pin. File preparation and SQL claims are distinct durable stages.
use super::*;
use crate::documents::CandidateState;
const CLAIMS: &str = "CREATE TABLE edit_candidate_core_claims(intent_id TEXT PRIMARY KEY REFERENCES edit_candidate_intents(intent_id),binding_json TEXT NOT NULL,candidate_id TEXT NOT NULL UNIQUE,operation_id TEXT NOT NULL,expected_digest TEXT NOT NULL,expected_length TEXT NOT NULL)";
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CoreCandidatePreparation {
    pub original_binding: Binding,
    pub candidate_id: String,
    pub operation_id: String,
    pub expected_blob: BlobRef,
    pub state: CandidateState,
}
struct Claim {
    candidate_id: String,
    operation_id: String,
    expected_blob: BlobRef,
}
fn identities(b: &Binding, blob: &BlobRef) -> Result<(String, String)> {
    let operation_id = format!("op:{}", hex(&b.patch_digest));
    let data = serde_json::to_vec(&("edited_core_candidate_v1", binding_json(b)?, blob))
        .map_err(|_| ContractError::InvalidPayload)?;
    Ok((format!("candidate:{}", sha(&data)), operation_id))
}
pub(super) fn initialize_core_bridge(store: &BusinessStore) -> Result<()> {
    store.initialize_document_candidates_trusted()?;
    let db = store.database();
    let tx = sql(db.transaction())?;
    let rows = sql(db.query(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='edit_candidate_core_claims'",
        &[],
    ))?;
    if rows.is_empty() {
        sql(db.exec(CLAIMS, &[]))?;
    } else if rows.len() != 1 || cell(&rows[0], 0)? != CLAIMS {
        return Err(ContractError::InvalidVersion);
    }
    sql(tx.commit())
}
impl EditedCandidateJournal<'_> {
    fn core_claim(&self, b: &Binding, expected: &BlobRef) -> Result<Option<Claim>> {
        let rows=sql(self.store.database().query("SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192 THEN binding_json END,CASE WHEN length(CAST(candidate_id AS BLOB))<=128 THEN candidate_id END,CASE WHEN length(CAST(operation_id AS BLOB))<=128 THEN operation_id END,CASE WHEN length(expected_digest)=64 THEN expected_digest END,CASE WHEN length(expected_length)<=20 THEN expected_length END FROM edit_candidate_core_claims WHERE intent_id=?",&[&b.intent_id]))?;
        let Some(row) = rows.first() else {
            return Ok(None);
        };
        let (candidate, operation) = identities(b, expected)?;
        if cell(row, 0)? != binding_json(b)?
            || cell(row, 1)? != candidate
            || cell(row, 2)? != operation
            || cell(row, 3)? != expected.digest
            || cell(row, 4)? != expected.byte_length.as_str()
        {
            return Err(ContractError::StorageCorrupt);
        }
        Ok(Some(Claim {
            candidate_id: candidate,
            operation_id: operation,
            expected_blob: expected.clone(),
        }))
    }
    fn original_core_status(
        &self,
        b: &Binding,
        a: &DocumentAccess,
        claim: &Claim,
    ) -> Result<CoreCandidatePreparation> {
        let state = match self.store.lookup_document_candidate(a, &claim.candidate_id) {
            Ok(actual) => {
                if actual.candidate_id != claim.candidate_id
                    || actual.operation_id != claim.operation_id
                    || actual.base != b.document
                    || actual.expected_blob != claim.expected_blob
                {
                    return Err(ContractError::BindingMismatch);
                }
                actual.state
            }
            // A claim with no core row may be a crash before core invocation.
            // Absence does not authorize any repeat of preparation.
            Err(ContractError::NotFound) => CandidateState::PreparationUnknown,
            Err(e) => return Err(e),
        };
        Ok(CoreCandidatePreparation {
            original_binding: b.clone(),
            candidate_id: claim.candidate_id.clone(),
            operation_id: claim.operation_id.clone(),
            expected_blob: claim.expected_blob.clone(),
            state,
        })
    }
    pub fn lookup_core_candidate(
        &self,
        b: &Binding,
        a: &DocumentAccess,
    ) -> Result<CoreCandidatePreparation> {
        let claim = {
            let tx = sql(self.store.database().transaction())?;
            self.authorize(
                &tx,
                b,
                a,
                &[
                    DocumentOperation::ReadText,
                    DocumentOperation::StructuredEdit,
                ],
                false,
            )?;
            let r = self.load(b)?;
            let expected = self.view(b, &r)?.candidate.ok_or(ContractError::NotFound)?;
            let claim = self
                .core_claim(b, &expected)?
                .ok_or(ContractError::NotFound)?;
            sql(tx.commit())?;
            claim
        };
        // The core query owns its transaction and verifies actual journal, original
        // pin/object bytes and current authority. Never call it inside our tx.
        let observed = self.original_core_status(b, a, &claim)?;
        let tx = sql(self.store.database().transaction())?;
        self.authorize(
            &tx,
            b,
            a,
            &[
                DocumentOperation::ReadText,
                DocumentOperation::StructuredEdit,
            ],
            false,
        )?;
        let current = self
            .view(b, &self.load(b)?)?
            .candidate
            .ok_or(ContractError::StorageCorrupt)?;
        self.core_claim(b, &current)?
            .ok_or(ContractError::StorageCorrupt)?;
        if current != claim.expected_blob {
            return Err(ContractError::BindingMismatch);
        }
        self.authorize(
            &tx,
            b,
            a,
            &[
                DocumentOperation::ReadText,
                DocumentOperation::StructuredEdit,
            ],
            false,
        )?;
        sql(tx.commit())?;
        Ok(observed)
    }
    /// Initiate one real private object preparation from the already-frozen local
    /// candidate. A recorded invocation always queries; it never resumes writes.
    pub fn prepare_core_candidate_trusted(
        &self,
        b: &Binding,
        a: &DocumentAccess,
    ) -> Result<CoreCandidatePreparation> {
        let payload = {
            let db = self.store.database();
            let tx = sql(db.transaction())?;
            let r = self.load(b)?;
            self.authorize(
                &tx,
                b,
                a,
                &[
                    DocumentOperation::ReadText,
                    DocumentOperation::StructuredEdit,
                ],
                false,
            )?;
            let view = self.view(b, &r)?;
            let expected = view.candidate.ok_or(ContractError::InvalidAuthority)?;
            if self.core_claim(b, &expected)?.is_some() {
                sql(tx.commit())?;
                None
            } else {
                self.effect(&tx, b, a, &r)?;
                if r.state != "candidate_unvalidated" {
                    return Err(ContractError::InvalidAuthority);
                }
                let data = bytes(&r)?;
                let (candidate, operation) = identities(b, &expected)?;
                sql(db.exec(
                    "INSERT INTO edit_candidate_core_claims VALUES(?,?,?,?,?,?)",
                    &[
                        &b.intent_id,
                        &binding_json(b)?,
                        &candidate,
                        &operation,
                        &expected.digest,
                        expected.byte_length.as_str(),
                    ],
                ))?;
                self.effect(&tx, b, a, &self.load(b)?)?;
                tx.commit().map_err(|_| ContractError::Unknown)?;
                Some((candidate, operation, data))
            }
        };
        let Some((candidate, operation, data)) = payload else {
            return self.lookup_core_candidate(b, a);
        };
        // A cancellation/expiry already visible after the invocation claim blocks
        // entry. In-flight core staging is separately durable, never rollbackable.
        let preflight = (|| {
            let tx = sql(self.store.database().transaction())?;
            self.effect(&tx, b, a, &self.load(b)?)?;
            sql(tx.commit())
        })();
        if preflight.is_err() {
            return Err(ContractError::Unknown);
        }
        self.store
            .prepare_document_candidate_trusted(a, &candidate, &operation, &data)
            .map_err(|_| ContractError::Unknown)?;
        let tx = sql(self.store.database().transaction())?;
        self.effect(&tx, b, a, &self.load(b)?)
            .map_err(|_| ContractError::Unknown)?;
        sql(tx.commit()).map_err(|_| ContractError::Unknown)?;
        self.lookup_core_candidate(b, a)
            .map_err(|_| ContractError::Unknown)
    }
}
