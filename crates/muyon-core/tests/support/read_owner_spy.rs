//! Test-only interception at the adapter's StoreEvidence import. Reads delegate
//! to the real owner; forbidden processing requests are counted and rejected,
//! never delegated to a processor or an OCR/embedding engine.
use muyon_core::{
    business::BusinessStore,
    documents::DocumentAccess,
    evidence::{
        store::{StoreEvidence as RealOwner, StoreEvidenceError, StoredProcessing},
        EvidenceError, EvidenceRef, InputKind,
    },
};
use std::cell::Cell;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub open: usize,
    pub processing: usize,
    pub parse_requests: usize,
    pub ocr_requests: usize,
}
thread_local! { static COUNTS: Cell<Counts> = Cell::new(Counts::default()); }
pub fn reset() {
    COUNTS.with(|cell| cell.set(Counts::default()));
}
pub fn counts() -> Counts {
    COUNTS.with(Cell::get)
}

pub struct StoreEvidence<'a>(RealOwner<'a>);
impl<'a> StoreEvidence<'a> {
    pub fn new(store: &'a BusinessStore) -> Self {
        Self(RealOwner::new(store))
    }
    pub fn open(
        &self,
        access: &DocumentAccess,
        processing: &StoredProcessing,
        reference: &EvidenceRef,
    ) -> Result<String, StoreEvidenceError> {
        COUNTS.with(|cell| {
            let mut n = cell.get();
            n.open += 1;
            cell.set(n);
        });
        self.0.open(access, processing, reference)
    }
    /// A fake unavailable work sink. It observes even a discarded/error-returned
    /// request and cannot start any real processing work.
    pub fn process(
        &self,
        _access: &DocumentAccess,
        kind: InputKind,
    ) -> Result<StoredProcessing, StoreEvidenceError> {
        COUNTS.with(|cell| {
            let mut n = cell.get();
            n.processing += 1;
            match kind {
                InputKind::Ocr => n.ocr_requests += 1,
                InputKind::Utf8Text | InputKind::Pdf => n.parse_requests += 1,
            }
            cell.set(n);
        });
        Err(StoreEvidenceError::Processing(EvidenceError::NotAvailable))
    }
}
