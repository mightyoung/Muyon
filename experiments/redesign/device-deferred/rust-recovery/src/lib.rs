//! Provisional host-only seam. Not a product schema, executor or durable store.
use std::collections::BTreeMap;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Domain { pub store: String, pub scope: String, pub stream: String }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cursor { pub domain: Domain, pub seq: u64 }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event { pub cursor: Cursor, pub payload: String }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Identity { pub intent: String, pub action: String, pub attempt: String, pub scope: String, pub parameters: String }
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Receipt { pub id: String, pub identity: Identity, pub effect: String }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome { Applied, Duplicate, WrongDomain, Conflict, Pull(Cursor), SnapshotRequired, StaleDisplay, Displayed, Verified, Unverified, NewIntent, Rejected }
#[derive(Clone, Debug)]
pub struct State {
    pub received: Cursor, pub applied: Cursor, pub committed: Cursor,
    pub projection: String, pub committed_projection: String,
    pub epoch: String, pub display: String, pub receipts: BTreeMap<String, Receipt>,
    pub unknown: BTreeMap<String, Identity>, pub synthetic_intents: BTreeMap<String, Identity>,
    pub buffered: BTreeMap<u64, Event>, pub limit: usize, pub snapshot_required: bool,
    seen: BTreeMap<u64, String>,
}
impl State {
    pub fn new(cursor: Cursor, projection: String, epoch: String, limit: usize) -> Self {
        Self { received:cursor.clone(), applied:cursor.clone(), committed:cursor, projection:projection.clone(), committed_projection:projection, epoch, display:String::new(), receipts:BTreeMap::new(), unknown:BTreeMap::new(), synthetic_intents:BTreeMap::new(), buffered:BTreeMap::new(), limit, snapshot_required:false, seen:BTreeMap::new() }
    }
    pub fn receive(&mut self, event: Event) -> Outcome {
        if event.cursor.domain != self.applied.domain { return Outcome::WrongDomain; }
        let seq=event.cursor.seq;
        if let Some(payload)=self.seen.get(&seq) {
            return if payload==&event.payload { Outcome::Duplicate } else { Outcome::Conflict };
        }
        if let Some(buffered)=self.buffered.get(&seq) {
            return if buffered==&event { Outcome::Duplicate } else { Outcome::Conflict };
        }
        if seq<=self.applied.seq { return Outcome::Duplicate; }
        self.received.seq=self.received.seq.max(seq);
        if self.snapshot_required { return Outcome::SnapshotRequired; }
        if self.applied.seq.checked_add(1)!=Some(seq) {
            if self.buffered.len()>=self.limit {
                self.snapshot_required=true;
                return Outcome::SnapshotRequired;
            }
            self.buffered.insert(seq,event);
            return Outcome::Pull(self.committed.clone());
        }
        self.apply(event);
        while let Some(next)=self.applied.seq.checked_add(1) {
            match self.buffered.remove(&next) { Some(event)=>self.apply(event), None=>break }
        }
        Outcome::Applied
    }
    fn apply(&mut self, event: Event) {
        self.seen.insert(event.cursor.seq,event.payload.clone());
        self.applied=event.cursor;
        self.projection=event.payload;
    }
    /// In-memory paired checkpoint only: caller must supply real atomic persistence.
    pub fn commit(&mut self) {
        self.committed=self.applied.clone();
        self.committed_projection=self.projection.clone();
    }
    pub fn reconnect(&mut self, epoch: String) {
        self.epoch=epoch;
        self.received=self.committed.clone();
        self.applied=self.committed.clone();
        self.projection=self.committed_projection.clone();
        self.seen.retain(|seq,_| *seq<=self.committed.seq);
        self.buffered.clear();
        self.snapshot_required=false;
    }
    pub fn display_callback(&mut self, epoch: &str, body: &str) -> Outcome {
        if epoch!=self.epoch { return Outcome::StaleDisplay; }
        self.display=body.into();
        Outcome::Displayed
    }
    /// Exact synthetic ledger verification, NOT source authentication or a digest protocol.
    pub fn reconcile(&mut self, expected: &Identity, hint: &Receipt, ledger: &[Receipt]) -> Outcome {
        if &hint.identity!=expected || hint.id.is_empty() || !ledger.iter().any(|entry| entry==hint) {
            return Outcome::Unverified;
        }
        if self.receipts.get(&hint.id).is_some_and(|existing| existing!=hint) { return Outcome::Unverified; }
        self.receipts.insert(hint.id.clone(),hint.clone());
        Outcome::Verified
    }
    /// Caller-injected synthetic trust seam; does not authorize or dispatch business.
    pub fn user_new_intent(&mut self, old: &str, new: Identity, trusted_instruction: Option<&str>) -> Outcome {
        let Some(original)=self.unknown.get(old) else {return Outcome::Rejected;};
        if trusted_instruction.is_none_or(str::is_empty) || new.intent.is_empty() ||
            self.unknown.contains_key(&new.intent) || self.synthetic_intents.contains_key(&new.intent) ||
            new.scope!=original.scope || new.action!=original.action || new.parameters!=original.parameters {
            return Outcome::Rejected;
        }
        self.synthetic_intents.insert(new.intent.clone(),new);
        Outcome::NewIntent
    }
}
