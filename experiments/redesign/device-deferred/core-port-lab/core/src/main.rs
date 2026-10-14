//! One synthetic laboratory executor. No real persistence or product authority.
use std::{collections::BTreeMap, io::{self, BufRead, Write}};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use rd_p01_domain_experiment::{ProvisionalSnapshot, normalize_raw, read_name, edit_candidate};
use provisional_recovery_reducer as recovery;

const FRAME_LIMIT: usize = 32768;
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Domain { store: String, scope: String, stream: String }
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Row { id: String, name: String, revision: String }
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct Faults {
    #[serde(default)] drop_commit_reply_once: bool,
    #[serde(default)] precommit_fail_once: bool,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Seed { lab_only: bool, domain: Domain, display_epoch: String, suppliers: Vec<Row>, trusted_faults: Faults }
#[derive(Deserialize, PartialEq, Eq)]
#[serde(rename_all="snake_case")]
enum Op { Hello, Snapshot, Preview, Commit, Lookup, Reconnect }
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    protocol: u32, request_id: String, op: Op, domain: Domain, display_epoch: String,
    #[serde(default, deserialize_with="nonnull")] object_id: Option<String>,
    #[serde(default, deserialize_with="nonnull")] intent: Option<String>,
    #[serde(default, deserialize_with="nonnull")] expected_revision: Option<String>,
    #[serde(default, deserialize_with="nonnull")] raw_utf16: Option<Vec<u16>>,
    #[serde(default, deserialize_with="nonnull")] plan_id: Option<String>,
    #[serde(default, deserialize_with="nonnull")] new_display_epoch: Option<String>,
}
#[derive(Clone, Serialize)]
struct Cursor { store: String, scope: String, stream: String, seq: String }
#[derive(Clone, Serialize)]
struct Snapshot { cursor: Cursor, suppliers: Vec<Row> }
#[derive(Clone, Serialize)]
struct Plan { id: String, intent: String, object_id: String, expected_revision: String, normalized_name: String, parameters_digest: String }
#[derive(Clone, Serialize)]
struct Receipt {
    kind: &'static str, id: String, intent: String, object_id: String, expected_revision: String,
    result_revision: String, normalized_name: String, parameters_digest: String, commit_cursor: Cursor,
}
#[derive(Serialize)]
struct Reply {
    protocol: u32, request_id: String, kind: &'static str, reason: Option<&'static str>,
    domain: Domain, display_epoch: String, display_admission: &'static str,
    snapshot: Option<Snapshot>, plan: Option<Plan>, receipt: Option<Receipt>,
}
#[derive(Clone, Serialize, PartialEq, Eq)]
struct Business { object_id: String, intent: String, expected_revision: String, raw_utf16: Vec<u16> }
#[derive(Clone)]
struct PlanEntry { business: Business, plan: Plan }
#[derive(Clone)]
struct Effect { business: Business, plan_id: String, receipt: Receipt, proof: recovery::Receipt }
#[derive(Clone)]
struct Core {
    domain: Domain, rows: Vec<Row>, reducer: recovery::State,
    plans: BTreeMap<String, PlanEntry>, effects: BTreeMap<String, Effect>, next_plan: u64,
    drop_reply: bool, precommit_fail: bool,
}
fn nonnull<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where D: serde::Deserializer<'de>, T: Deserialize<'de> {
    T::deserialize(deserializer).map(Some)
}
fn decimal(s: &str) -> Option<u64> {
    if s.is_empty() || (s.len()>1 && s.starts_with('0')) || !s.bytes().all(|b| b.is_ascii_digit()) { return None; }
    s.parse().ok()
}
fn label(s: &str) -> bool { !s.is_empty() && s.len() <= 128 }
fn recovery_domain(d: &Domain) -> recovery::Domain { recovery::Domain { store:d.store.clone(), scope:d.scope.clone(), stream:d.stream.clone() } }
fn cursor(d: &Domain, seq: u64) -> Cursor { Cursor { store:d.store.clone(), scope:d.scope.clone(), stream:d.stream.clone(), seq:seq.to_string() } }
impl Core {
    fn from_seed(seed: Seed) -> Result<Self, &'static str> {
        if !seed.lab_only || !label(&seed.domain.store) || !label(&seed.domain.scope) || !label(&seed.domain.stream) || !label(&seed.display_epoch) { return Err("invalid_seed"); }
        let mut ids = BTreeMap::new();
        for row in &seed.suppliers {
            if !label(&row.id) || decimal(&row.revision).is_none_or(|n| n==0) || ids.insert(row.id.clone(),()).is_some() || normalize_raw(&row.name.encode_utf16().collect::<Vec<_>>()).as_ref()!=Ok(&row.name) { return Err("invalid_seed"); }
        }
        let projection = serde_json::to_string(&seed.suppliers).map_err(|_| "invalid_seed")?;
        let reducer = recovery::State::new(recovery::Cursor { domain:recovery_domain(&seed.domain), seq:0 },projection,seed.display_epoch,128);
        Ok(Self { domain:seed.domain, rows:seed.suppliers, reducer, plans:BTreeMap::new(), effects:BTreeMap::new(),next_plan:0,drop_reply:seed.trusted_faults.drop_commit_reply_once,precommit_fail:seed.trusted_faults.precommit_fail_once })
    }
    fn reply(&self, id: &str, epoch: &str, kind: &'static str, reason: Option<&'static str>) -> Reply {
        Reply { protocol:0, request_id:id.into(),kind,reason,domain:self.domain.clone(),display_epoch:epoch.into(), display_admission:if epoch==self.reducer.epoch {"current"} else {"stale"}, snapshot:None,plan:None,receipt:None }
    }
    fn snapshot(&self) -> Snapshot { Snapshot { cursor:cursor(&self.domain,self.reducer.committed.seq),suppliers:self.rows.clone() } }
    fn domain_snapshot(&self, row: &Row) -> ProvisionalSnapshot { ProvisionalSnapshot { scope:self.domain.scope.clone(),supplier_id:row.id.clone(),name:row.name.clone(),revision:decimal(&row.revision).unwrap(),deleted:false } }
    fn identity(&self, plan: &Plan) -> recovery::Identity { recovery::Identity { intent:plan.intent.clone(),action:"supplier.name".into(),attempt:plan.id.clone(),scope:self.domain.scope.clone(),parameters:plan.parameters_digest.clone() } }
    fn shape(req: &Request) -> Result<Option<Business>, &'static str> {
        if req.protocol!=0 || !label(&req.request_id) || !label(&req.display_epoch) { return Err("invalid_request"); }
        if !label(&req.domain.store) || !label(&req.domain.scope) || !label(&req.domain.stream) { return Err("invalid_request"); }
        let business = matches!(req.op,Op::Preview|Op::Commit|Op::Lookup);
        if business {
            if req.new_display_epoch.is_some() { return Err("invalid_request"); }
            let b=Business { object_id:req.object_id.clone().ok_or("invalid_request")?,intent:req.intent.clone().ok_or("invalid_request")?,expected_revision:req.expected_revision.clone().ok_or("invalid_request")?,raw_utf16:req.raw_utf16.clone().ok_or("invalid_request")? };
            if !label(&b.object_id) || !label(&b.intent) || decimal(&b.expected_revision).is_none_or(|n|n==0) { return Err("invalid_request"); }
            if req.op==Op::Preview { if req.plan_id.is_some() { return Err("invalid_request"); } }
            else if req.plan_id.as_deref().is_none_or(|s| !label(s)) { return Err("invalid_request"); }
            Ok(Some(b))
        } else {
            if req.object_id.is_some() || req.intent.is_some() || req.expected_revision.is_some() || req.raw_utf16.is_some() || req.plan_id.is_some() { return Err("invalid_request"); }
            if req.op==Op::Reconnect { if req.new_display_epoch.as_deref().is_none_or(|s| !label(s)) { return Err("invalid_request"); } }
            else if req.new_display_epoch.is_some() { return Err("invalid_request"); }
            Ok(None)
        }
    }
    fn handle(&mut self, req: Request) -> Reply {
        let mut reply=self.reply(&req.request_id,&req.display_epoch,"rejected",None);
        let business=match Self::shape(&req) { Ok(b)=>b,Err(e)=>{return self.reply("","","rejected",Some(e));} };
        if req.domain!=self.domain { reply.reason=Some("domain_mismatch");return reply; }
        match req.op {
            Op::Hello | Op::Snapshot => { reply.kind=if req.op==Op::Hello {"hello"} else {"snapshot"};reply.snapshot=Some(self.snapshot());reply }
            Op::Reconnect => {
                self.reducer.reconnect(req.new_display_epoch.clone().unwrap());
                let mut r=self.reply(&req.request_id,&self.reducer.epoch,"snapshot",None);r.snapshot=Some(self.snapshot());r
            }
            Op::Preview => self.preview(req,business.unwrap()),
            Op::Commit => self.commit(req,business.unwrap()),
            Op::Lookup => self.lookup(req,business.unwrap()),
        }
    }
    fn preview(&mut self, req: Request, business: Business) -> Reply {
        let mut r=self.reply(&req.request_id,&req.display_epoch,"rejected",None);
        let Some(row)=self.rows.iter().find(|row|row.id==business.object_id) else {r.reason=Some("missing_object");return r;};
        let source=self.domain_snapshot(row);
        if read_name(&source,&self.domain.scope,&business.object_id).is_err() {r.reason=Some("scope");return r;}
        let candidate=match edit_candidate(&source,&self.domain.scope,&business.object_id,decimal(&business.expected_revision).unwrap(),&business.raw_utf16) {
            Ok(c)=>c,Err(rd_p01_domain_experiment::DomainError::Revision)=>{r.kind="conflict";r.reason=Some("revision_conflict");return r;},Err(_)=>{r.reason=Some("invalid_name");return r;}
        };
        if let Some(existing)=self.plans.values().find(|p|p.business.intent==business.intent) {
            if existing.business!=business {r.kind="conflict";r.reason=Some("intent_conflict");return r;}
            r.kind="prepared";r.plan=Some(existing.plan.clone());return r;
        }
        let Some(number)=self.next_plan.checked_add(1) else {r.reason=Some("counter_overflow");return r;};
        let id=format!("lab-plan-{number}");
        let bytes=serde_json::to_vec(&(&self.domain.store,&self.domain.scope,"supplier.name",&business,&id)).unwrap();
        let digest: String=Sha256::digest(bytes).iter().map(|byte|format!("{byte:02x}")).collect();
        let plan=Plan { id:id.clone(),intent:business.intent.clone(),object_id:business.object_id.clone(),expected_revision:business.expected_revision.clone(),normalized_name:candidate.normalized_name,parameters_digest:digest };
        self.next_plan=number;self.plans.insert(id,PlanEntry {business,plan:plan.clone()});r.kind="prepared";r.plan=Some(plan);r
    }
    fn commit(&mut self, req: Request, business: Business) -> Reply {
        let mut r=self.reply(&req.request_id,&req.display_epoch,"rejected",None);
        let plan_id=req.plan_id.as_deref().unwrap();
        // DUPLICATE_GUARD: replay original receipt before obsolete CAS is checked.
        if let Some(effect)=self.effects.get(&business.intent) {
            if effect.business!=business || effect.plan_id!=plan_id {r.kind="conflict";r.reason=Some("intent_conflict");return r;}
            r.kind="committed";r.receipt=Some(effect.receipt.clone());r.snapshot=Some(self.snapshot());return r;
        }
        let Some(entry)=self.plans.get(plan_id) else {r.reason=Some("unknown_plan");return r;};
        if entry.business!=business {r.kind="conflict";r.reason=Some("plan_conflict");return r;}
        let plan=entry.plan.clone();
        let Some(index)=self.rows.iter().position(|row|row.id==business.object_id) else {r.reason=Some("missing_object");return r;};
        let source=self.domain_snapshot(&self.rows[index]);
        // CAS_GUARD: actual current row is revalidated at the execution boundary.
        let candidate=match edit_candidate(&source,&self.domain.scope,&business.object_id,decimal(&business.expected_revision).unwrap(),&business.raw_utf16) {
            Ok(c)=>c,Err(rd_p01_domain_experiment::DomainError::Revision)=>{r.kind="conflict";r.reason=Some("revision_conflict");return r;},Err(_)=>{r.reason=Some("invalid_name");return r;}
        };
        let Some(seq)=self.reducer.committed.seq.checked_add(1) else {r.reason=Some("counter_overflow");return r;};
        let mut staged=self.clone();
        staged.rows[index].name=candidate.normalized_name.clone();staged.rows[index].revision=candidate.candidate_revision.to_string();
        let event=recovery::Event { cursor:recovery::Cursor {domain:recovery_domain(&self.domain),seq},payload:serde_json::to_string(&staged.rows).unwrap() };
        if staged.reducer.receive(event)!=recovery::Outcome::Applied {r.reason=Some("reducer_conflict");return r;}
        staged.reducer.commit();
        let receipt=Receipt { kind:"synthetic",id:format!("lab-receipt-{seq}"),intent:business.intent.clone(),object_id:business.object_id.clone(),expected_revision:business.expected_revision.clone(),result_revision:candidate.candidate_revision.to_string(),normalized_name:candidate.normalized_name,parameters_digest:plan.parameters_digest.clone(),commit_cursor:cursor(&self.domain,seq) };
        let proof=recovery::Receipt { id:receipt.id.clone(),identity:self.identity(&plan),effect:serde_json::to_string(&receipt).unwrap() };
        staged.effects.insert(business.intent.clone(),Effect {business:business.clone(),plan_id:plan_id.into(),receipt:receipt.clone(),proof:proof.clone()});
        if self.precommit_fail {self.precommit_fail=false;r.reason=Some("injected_precommit_failure");return r;}
        let drop_reply=staged.drop_reply;
        staged.drop_reply=false;
        if drop_reply {staged.reducer.unknown.insert(business.intent.clone(),proof.identity.clone());}
        *self=staged; // Single staged swap: row, checkpoint and receipt ledger together.
        if drop_reply {r.kind="unknown";r.reason=Some("commit_reply_lost");return r;}
        r.kind="committed";r.snapshot=Some(self.snapshot());r.receipt=Some(receipt);r
    }
    fn lookup(&mut self, req: Request, business: Business) -> Reply {
        let mut r=self.reply(&req.request_id,&req.display_epoch,"unknown",Some("receipt_unavailable"));
        let Some(effect)=self.effects.get(&business.intent).cloned() else {return r;};
        if effect.business!=business || Some(effect.plan_id.as_str())!=req.plan_id.as_deref() {r.kind="conflict";r.reason=Some("intent_conflict");return r;}
        let ledger:Vec<_>=self.effects.values().map(|e|e.proof.clone()).collect();
        if self.reducer.reconcile(&effect.proof.identity,&effect.proof,&ledger)!=recovery::Outcome::Verified {r.reason=Some("receipt_unverified");return r;}
        self.reducer.unknown.remove(&business.intent);
        r.kind="committed";r.reason=None;r.receipt=Some(effect.receipt);r.snapshot=Some(self.snapshot());
        // Verified effect and presentation are independent axes: large projection
        // cannot permanently prevent recovery of the already checked receipt.
        if serde_json::to_vec(&r).unwrap().len()>FRAME_LIMIT {r.snapshot=None;}
        r
    }
    fn frame(&mut self, frame: &[u8]) -> Reply {
        match serde_json::from_slice::<Request>(frame) {
            Ok(req)=>self.handle(req),
            Err(_)=>self.reply("","","rejected",Some("invalid_request"))
        }
    }
}
fn run() -> Result<(), &'static str> {
    let args:Vec<_>=std::env::args().collect();
    if args.len()!=3 || args[1]!="--seed" {return Err("invalid_startup_arguments");}
    let bytes=std::fs::read(&args[2]).map_err(|_|"seed_unavailable")?;
    if bytes.len()>FRAME_LIMIT {return Err("invalid_seed");}
    let seed=serde_json::from_slice(&bytes).map_err(|_|"invalid_seed")?;
    let mut core=Core::from_seed(seed)?;
    let mut input=io::stdin().lock();let mut output=io::stdout().lock();
    loop {
        let mut frame=Vec::new();let mut oversized=false;let mut ended=false;
        loop {
            let buffer=input.fill_buf().map_err(|_|"input_unavailable")?;
            if buffer.is_empty() {ended=true;break;}
            let newline=buffer.iter().position(|b|*b==b'\n');let used=newline.map_or(buffer.len(),|n|n+1);
            let data_len=newline.unwrap_or(used);
            if !oversized {if frame.len()+data_len>FRAME_LIMIT {oversized=true;frame.clear();} else {frame.extend_from_slice(&buffer[..data_len]);}}
            input.consume(used);if newline.is_some(){break;}
        }
        if ended {break;} // Unterminated EOF is not a valid NDJSON request.
        let reply=if oversized {core.reply("","","rejected",Some("frame_limit"))} else {core.frame(&frame)};
        let mut data=serde_json::to_vec(&reply).map_err(|_|"reply_unavailable")?;
        if data.len()>FRAME_LIMIT {
            // An output limit never proves absence of an already staged effect.
            let unavailable=core.reply(&reply.request_id,&reply.display_epoch,"unknown",Some("reply_limit"));
            data=serde_json::to_vec(&unavailable).map_err(|_|"reply_unavailable")?;
        }
        output.write_all(&data).and_then(|_|output.write_all(b"\n")).and_then(|_|output.flush()).map_err(|_|"output_unavailable")?;
    }
    Ok(())
}
fn main() {if let Err(reason)=run(){eprintln!("{reason}");std::process::exit(2);}}
