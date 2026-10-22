//! Trusted native continuation of an exact already-authorized reading intent.
//! Host/FFI supplies real scope/surface observations. No initial no-grant issuer.
mod types;
mod store;
pub use types::{PolicyResult, PolicyScope, ReadingSurfaceBinding, PolicyAvailability, PolicyKind, PolicyOutcomeStatus, PolicyHandoffState, PolicyRootState, PolicyStopReason, PolicyObserveRequest, PolicyBeginRequest, PolicyPrepareRequest, PolicyRenewRequest, PolicyReconcileRequest, PolicyStopRequest, PolicyContinueRequest, PolicyObservation, OriginalPolicyOutcome, PreparedPolicyOutcome, PolicyContinuation};
pub(super) use types::GrantRecord;
use types::{RootRecord, AttemptRecord};
use super::{identity::valid_id, reader::{DocumentReaderHost, PresentationTicket, DocumentReadError}, storage, DocumentAccess, DocumentOperation};
use crate::{business::BusinessStore, contract::{AuthorityBinding, ContractError, Revision}, sqlite::Transaction};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{collections::{BTreeMap, BTreeSet}, time::{Duration, Instant}};
pub const MAX_POLICY_ROOTS: usize=16;
pub const MAX_POLICY_ATTEMPTS: usize=256;
const FRESH: Duration=Duration::from_millis(2000);
fn sql<T>(value: crate::sqlite::Result<T>)->PolicyResult<T>{value.map_err(|_|ContractError::Storage)}
fn hash(text:&str)->String{Sha256::digest(text.as_bytes()).iter().map(|v|format!("{v:02x}")).collect()}
fn fingerprint<T:Serialize>(value:&T)->PolicyResult<String>{Ok(hash(&store::json(value)?))}
fn id_shape(id:&str)->PolicyResult<()>{if valid_id(id){Ok(())}else{Err(ContractError::InvalidIdentity)}}
fn scope_shape(value:&PolicyScope)->PolicyResult<()>{id_shape(&value.service_session)?;id_shape(&value.project)?;if value.generation.value()==0{return Err(ContractError::InvalidRevision);}Ok(())}
fn surface_shape(value:&ReadingSurfaceBinding)->PolicyResult<()>{id_shape(&value.surface_id)?;id_shape(&value.lifecycle_epoch)?;if value.selection_sequence.value()==0{return Err(ContractError::InvalidRevision);}Ok(())}
fn read_error(error:DocumentReadError)->ContractError{match error{DocumentReadError::Core(error)=>error,DocumentReadError::Cleanup{..}=>ContractError::Unknown}}
fn key(scope:&PolicyScope,kind:PolicyKind,id:&str)->PolicyResult<String>{Ok(format!("{}:{kind:?}:{id}",store::scope_key(scope)?))}
fn historical(mut value:OriginalPolicyOutcome)->OriginalPolicyOutcome{value.historical=true;value}
fn grant_same(expected:&GrantRecord,actual:&GrantRecord)->bool{actual.active && expected.access==actual.access && expected.operations==actual.operations}
fn validate_root(store:&BusinessStore,tx:&Transaction<'_>,root:&RootRecord,valid_current:bool)->PolicyResult<()> {
    if root.owner_epoch!=store.owner_epoch() || root.metadata.document.scope().workspace_id!=store.workspace_id(){return Err(ContractError::InvalidAuthority);}
    let current=store.reading_policy_metadata_in_transaction(tx,&root.metadata.document)?;if current!=root.metadata{return Err(ContractError::BindingMismatch);}
    let parent=store.reading_policy_grant_record_in_transaction(tx,&root.parent.access.authority.grant_id)?.ok_or(ContractError::InvalidAuthority)?;
    let grant=store.reading_policy_grant_record_in_transaction(tx,&root.current.access.authority.grant_id)?.ok_or(ContractError::InvalidAuthority)?;
    if !grant_same(&root.parent,&parent)||!grant_same(&root.current,&grant)||root.readonly_operations.iter().any(|op|!parent.operations.contains(op)||!op.is_read()){return Err(ContractError::InvalidAuthority);}
    if valid_current && (grant.expires_at_ms<=storage::now_ms()? || grant.expires_at_ms!=root.current.expires_at_ms){return Err(ContractError::InvalidAuthority);}
    Ok(())
}
fn outcome(store:&BusinessStore,scope:&PolicyScope,kind:PolicyKind,id:&str,fp:String,status:PolicyOutcomeStatus,root:Option<&RootRecord>)->PolicyResult<OriginalPolicyOutcome>{
    Ok(OriginalPolicyOutcome{schema:1,kind,original_attempt_id:id.into(),fingerprint:fp,outcome_id:store::native_id(store,"reader-outcome")?,status,scope:scope.clone(),root_id:root.map(|r|r.id.clone()),root_revision:root.map(|r|r.revision.clone()),root_state:root.map(|_|PolicyRootState::Active),readonly_operations:root.map(|r|r.readonly_operations.clone()).unwrap_or_default(),native_selection_epoch:root.map(|r|r.selection_epoch.clone()),access:root.map(|r|r.current.access.clone()),source_digest:root.map(|r|r.metadata.blob.digest.clone()),surface_binding:root.map(|r|r.surface.clone()),presentation_id:root.map(|r|r.presentation_id.clone()),frame_generation:root.map(|r|r.frame.clone()),challenge_id:None,continuation_token:None,valid_for_ms:None,issued_at_ms:None,expires_at_ms:root.map(|r|r.current.expires_at_ms),handoff:None,cleanup_pending:false,historical:false})
}
/// One native owner instance. Methods borrow the EXISTING reader per call.
/// All caller correlations are private Service facts, never Android visibility.
pub struct ReadingPolicyHost {
    instance:String,workspace:String,epoch:String,last_wall:u64,
    selection:Option<(PolicyScope,Revision)>,tickets:BTreeMap<String,PresentationTicket>,
    freshness:BTreeMap<String,Instant>,uncertain:BTreeSet<String>,
}
impl ReadingPolicyHost {
    pub fn open(reader:&mut DocumentReaderHost)->PolicyResult<Self>{
        if reader.policy_owner().is_some(){return Err(ContractError::InvalidAuthority);}
        store::initialize(reader.store())?;
        let instance=store::native_id(reader.store(),"reader-owner")?;
        let workspace=reader.store().workspace_id().to_string();let epoch=reader.store().owner_epoch().to_string();
        reader.policy_set_owner(instance.clone())?;
        Ok(Self{instance,workspace,epoch,last_wall:0,selection:None,tickets:BTreeMap::new(),freshness:BTreeMap::new(),uncertain:BTreeSet::new()})
    }
    fn ready(&self,reader:&DocumentReaderHost)->PolicyResult<()>{if reader.policy_owner()!=Some(self.instance.as_str()) || reader.store().workspace_id()!=self.workspace || reader.store().owner_epoch()!=self.epoch{return Err(ContractError::InvalidAuthority);}store::schema(reader.store())}
    fn now(&mut self)->PolicyResult<u64>{let now=storage::now_ms()?;if now<self.last_wall{return Err(ContractError::Unknown);}self.last_wall=now;Ok(now)}
    fn selected(&self,scope:&PolicyScope,epoch:&Revision)->PolicyResult<()>{scope_shape(scope)?;if self.selection.as_ref()!=Some(&(scope.clone(),epoch.clone())){return Err(ContractError::Cancelled);}Ok(())}
    fn root(&self,reader:&DocumentReaderHost,scope:&PolicyScope,id:&str)->PolicyResult<RootRecord>{
        self.ready(reader)?;let(root,terminal)=store::root(reader.store(),id)?;
        if root.scope!=*scope || root.instance!=self.instance || root.owner_epoch!=self.epoch{return Err(ContractError::ScopeMismatch);}
        if terminal{return Err(ContractError::Cancelled);}self.selected(scope,&root.selection_epoch)?;Ok(root)
    }
    fn track<T>(&mut self,k:String,result:PolicyResult<T>)->PolicyResult<T>{if result.as_ref().is_err_and(|e|matches!(e,ContractError::Storage|ContractError::StorageBusy|ContractError::StorageConstraint|ContractError::StorageCorrupt|ContractError::StorageIo|ContractError::Unknown)){self.uncertain.insert(k);}result}
    fn ticket(&self,root:&RootRecord)->PolicyResult<PresentationTicket>{let ticket=self.tickets.get(&root.id).ok_or(ContractError::Unknown)?;if ticket.session_id()!=root.core_session_id || ticket.document()!=&root.metadata.document || ticket.generation()!=&root.frame{return Err(ContractError::BindingMismatch);}Ok(ticket.clone())}
    pub fn observe(&mut self,reader:&mut DocumentReaderHost,request:&PolicyObserveRequest)->PolicyResult<PolicyObservation>{
        self.ready(reader)?;scope_shape(&request.scope)?;
        if request.access.document.scope().project_id.as_deref()!=Some(request.scope.project.as_str()) || request.access.document.scope().workspace_id!=self.workspace{return Err(ContractError::ScopeMismatch);}
        let now=self.now()?;let tx=sql(reader.store().database().transaction())?;
        let record=reader.store().reading_policy_grant_record_in_transaction(&tx,&request.access.authority.grant_id)?;
        let mut result=PolicyObservation{schema:1,document:request.access.document.clone(),source_digest:None,grant_id:request.access.authority.grant_id.clone(),grant_generation:request.access.authority.generation.clone(),active:None,expires_at_ms:None,now_ms:now,readonly_operations:Vec::new(),availability:PolicyAvailability::Unavailable};
        if let Some(record)=record{
            if record.access.document!=request.access.document || record.access.authority.owner_epoch!=self.epoch || request.access.authority.owner_epoch!=self.epoch { /* No classification of an unrelated target. */ }
            else if record.access.authority.generation!=request.access.authority.generation {result.availability=PolicyAvailability::Replaced;}
            else if record.access==request.access {
                result.active=Some(record.active);result.expires_at_ms=Some(record.expires_at_ms);
                result.readonly_operations=record.operations.iter().copied().filter(|op|op.is_read()).collect();
                result.availability=if !record.active{PolicyAvailability::Revoked}else if !record.operations.contains(&DocumentOperation::Render){PolicyAvailability::Unavailable}else if record.expires_at_ms<=now{PolicyAvailability::NaturallyExpired}else{PolicyAvailability::Valid};
                match reader.store().reading_policy_metadata_in_transaction(&tx,&request.access.document){Ok(metadata)=>result.source_digest=Some(metadata.blob.digest),Err(ContractError::RevisionConflict|ContractError::NotFound|ContractError::BindingMismatch|ContractError::ScopeMismatch)=>{result.availability=PolicyAvailability::Unavailable;},Err(error)=>return Err(error)}
            }
        }
        tx.commit().map_err(|_|ContractError::Unknown)?;Ok(result)
    }
    pub fn begin(&mut self,reader:&mut DocumentReaderHost,request:&PolicyBeginRequest,initial:&PresentationTicket,native_selection_epoch:&Revision)->PolicyResult<OriginalPolicyOutcome>{
        self.ready(reader)?;scope_shape(&request.scope)?;surface_shape(&request.surface_binding)?;id_shape(&request.original_attempt_id)?;id_shape(&request.presentation_id)?;
        let k=key(&request.scope,PolicyKind::Begin,&request.original_attempt_id)?;if self.uncertain.contains(&k){return Err(ContractError::Unknown);}
        let fp=fingerprint(&(request,native_selection_epoch))?;
        let result=(||{
            let tx=sql(reader.store().database().transaction())?;
            if let Some((old,_))=store::attempt(reader.store(),&request.scope,PolicyKind::Begin,&request.original_attempt_id)?{if old.fingerprint!=fp{return Err(ContractError::BindingMismatch);}return Ok(historical(old.outcome));}
            self.selected(&request.scope,native_selection_epoch)?;
            if request.access.document.scope().project_id.as_deref()!=Some(request.scope.project.as_str()) || initial.generation()!=&request.frame_generation{return Err(ContractError::BindingMismatch);}
            let metadata=reader.store().reading_policy_metadata_in_transaction(&tx,&request.access.document)?;
            if metadata.blob.digest!=request.source_digest{return Err(ContractError::BindingMismatch);}
            reader.policy_validate_selection(initial,&self.instance,&store::scope_key(&request.scope)?,native_selection_epoch)?;
            reader.policy_validate_begin(&tx,initial,&request.access,&metadata)?;
            let parent=reader.store().reading_policy_grant_record_in_transaction(&tx,&request.access.authority.grant_id)?.ok_or(ContractError::InvalidAuthority)?;
            if parent.access!=request.access || !parent.active || parent.expires_at_ms<=self.now()? || !parent.operations.contains(&DocumentOperation::Render){return Err(ContractError::InvalidAuthority);}
            let mut readonly_operations=Vec::new();for op in &parent.operations{if op.is_read()&&!readonly_operations.contains(op){readonly_operations.push(*op);}}
            let root=RootRecord{id:store::native_id(reader.store(),"reader-root")?,instance:self.instance.clone(),owner_epoch:self.epoch.clone(),scope:request.scope.clone(),surface:request.surface_binding.clone(),selection_epoch:native_selection_epoch.clone(),revision:Revision::new(1),metadata,parent:parent.clone(),current:parent,child_id:None,presentation_id:request.presentation_id.clone(),core_session_id:initial.session_id().into(),frame:initial.generation().clone(),readonly_operations,pending_renew:None,stop_fingerprint:None,stop_outcome:None};
            if store::json(&root)?.len()>8000{return Err(ContractError::TextLimit);}
            let result=outcome(reader.store(),&request.scope,PolicyKind::Begin,&request.original_attempt_id,fp.clone(),PolicyOutcomeStatus::Begun,Some(&root))?;
            let attempt=AttemptRecord{kind:PolicyKind::Begin,scope:request.scope.clone(),id:request.original_attempt_id.clone(),fingerprint:fp.clone(),prepared:None,root_id:Some(root.id.clone()),renew_fingerprint:None,observation_id:None,outcome:result.clone(),handoff_fingerprint:None,handoff_outcome:None};
            store::insert_root(reader.store(),&root)?;store::insert_attempt(reader.store(),&attempt,"begun")?;
            validate_root(reader.store(),&tx,&root,true)?;reader.policy_validate_begin(&tx,initial,&request.access,&root.metadata)?;
            reader.policy_validate_selection(initial,&self.instance,&store::scope_key(&request.scope)?,native_selection_epoch)?;
            store::assert_root(reader.store(),&root,false)?;store::assert_attempt(reader.store(),&attempt)?;
            self.tickets.insert(root.id.clone(),initial.clone());
            tx.commit().map_err(|_|ContractError::Unknown)?;Ok(result)
        })();self.track(k,result)
    }
    pub fn prepare(&mut self,reader:&mut DocumentReaderHost,request:&PolicyPrepareRequest)->PolicyResult<PreparedPolicyOutcome>{
        self.ready(reader)?;surface_shape(&request.surface_binding)?;id_shape(&request.original_attempt_id)?;let k=key(&request.scope,PolicyKind::Renew,&request.original_attempt_id)?;if self.uncertain.contains(&k){return Err(ContractError::Unknown);}let fp=fingerprint(request)?;let start=Instant::now();
        let result=(||{
            let tx=sql(reader.store().database().transaction())?;
            if let Some((old,_))=store::attempt(reader.store(),&request.scope,PolicyKind::Renew,&request.original_attempt_id)?{if old.fingerprint!=fp{return Err(ContractError::BindingMismatch);}return Ok(historical(old.outcome));}
            let root=self.root(reader,&request.scope,&request.root_id)?;
            if root.revision!=request.expected_root_revision || root.current.access.authority.grant_id!=request.expected_grant_id || root.current.access.authority.generation!=request.expected_grant_generation || root.surface!=request.surface_binding || root.presentation_id!=request.expected_presentation_id || root.frame!=request.expected_frame_generation || root.pending_renew.is_some(){return Err(ContractError::BindingMismatch);}
            validate_root(reader.store(),&tx,&root,false)?;
            let current=reader.store().reading_policy_grant_record_in_transaction(&tx,&root.current.access.authority.grant_id)?.ok_or(ContractError::InvalidAuthority)?;
            reader.policy_predecessor(&tx,&self.ticket(&root)?,current.expires_at_ms<=self.now()?)?;
            let mut result=outcome(reader.store(),&request.scope,PolicyKind::Renew,&request.original_attempt_id,fp.clone(),PolicyOutcomeStatus::Prepared,Some(&root))?;
            let challenge=store::native_id(reader.store(),"reader-challenge")?;result.challenge_id=Some(challenge.clone());result.valid_for_ms=Some(2000);
            let attempt=AttemptRecord{kind:PolicyKind::Renew,scope:request.scope.clone(),id:request.original_attempt_id.clone(),fingerprint:fp.clone(),prepared:Some(request.clone()),root_id:Some(root.id.clone()),renew_fingerprint:None,observation_id:None,outcome:result.clone(),handoff_fingerprint:None,handoff_outcome:None};
            store::insert_attempt(reader.store(),&attempt,"prepared")?;
            validate_root(reader.store(),&tx,&root,false)?;store::assert_root(reader.store(),&root,false)?;store::assert_attempt(reader.store(),&attempt)?;
            tx.commit().map_err(|_|ContractError::Unknown)?;self.freshness.insert(challenge,start);Ok(result)
        })();self.track(k,result)
    }
    /// D: consume a native monotonic challenge and atomically issue only the
    /// root-owned readonly child. The shared parent is never modified.
    pub fn renew(&mut self,reader:&mut DocumentReaderHost,request:&PolicyRenewRequest)->PolicyResult<OriginalPolicyOutcome>{
        self.ready(reader)?;scope_shape(&request.scope)?;surface_shape(&request.surface_binding)?;
        id_shape(&request.root_id)?;id_shape(&request.original_attempt_id)?;id_shape(&request.challenge_id)?;id_shape(&request.observation_id)?;
        let k=key(&request.scope,PolicyKind::Renew,&request.original_attempt_id)?;
        if self.uncertain.contains(&k){return Err(ContractError::Unknown);}
        let fp=fingerprint(request)?;
        let (mut attempt,fenced)=store::attempt(reader.store(),&request.scope,PolicyKind::Renew,&request.original_attempt_id)?.ok_or(ContractError::NotFound)?;
        if let Some(old)=&attempt.renew_fingerprint {
            if old!=&fp{return Err(ContractError::BindingMismatch);}
            // Historical evidence is immutable, never a fresh grant or lease.
            return Ok(historical(attempt.outcome));
        }
        if fenced || attempt.outcome.status!=PolicyOutcomeStatus::Prepared || attempt.outcome.challenge_id.as_deref()!=Some(request.challenge_id.as_str()){return Err(ContractError::Cancelled);}
        let started=self.freshness.remove(&request.challenge_id).ok_or(ContractError::Cancelled)?;
        if started.elapsed()>FRESH{return Err(ContractError::Cancelled);}
        let ticket_and_result=(||{
            let tx=sql(reader.store().database().transaction())?;
            let mut root=self.root(reader,&request.scope,&request.root_id)?;
            let prepared=attempt.prepared.as_ref().ok_or(ContractError::StorageCorrupt)?;
            if attempt.root_id.as_deref()!=Some(root.id.as_str()) || root.pending_renew.is_some() || root.revision!=request.expected_root_revision || root.revision!=prepared.expected_root_revision || root.surface!=request.surface_binding || root.surface!=prepared.surface_binding || root.presentation_id!=prepared.expected_presentation_id || root.frame!=prepared.expected_frame_generation || root.current.access.authority.grant_id!=prepared.expected_grant_id || root.current.access.authority.generation!=prepared.expected_grant_generation{return Err(ContractError::BindingMismatch);}
            validate_root(reader.store(),&tx,&root,false)?;
            let previous=self.ticket(&root)?;
            let actual=reader.store().reading_policy_grant_record_in_transaction(&tx,&root.current.access.authority.grant_id)?.ok_or(ContractError::InvalidAuthority)?;
            reader.policy_predecessor(&tx,&previous,actual.expires_at_ms<=self.now()?)?;
            let plan=reader.store().prepare_document_source_mutation_in_transaction(&tx,&[&root.metadata.document])?;
            store::begin_renew_guard(reader.store(),&root)?;
            let now=self.now()?;
            let child_id=match &root.child_id{Some(id)=>id.clone(),None=>store::native_id(reader.store(),"reader-child")?};
            let generation=if root.child_id.is_some(){root.current.access.authority.generation.next()?}else{Revision::new(1)};
            let next=GrantRecord{access:DocumentAccess{document:root.metadata.document.clone(),authority:AuthorityBinding{grant_id:child_id.clone(),generation,owner_epoch:self.epoch.clone()}},operations:root.readonly_operations.clone(),expires_at_ms:now.checked_add(30_000).ok_or(ContractError::InvalidAuthority)?,active:true};
            store::issue_child(reader.store(),&tx,&root,&next)?;
            root.child_id=Some(child_id);root.current=next;root.revision=root.revision.next()?;root.pending_renew=Some(request.original_attempt_id.clone());
            let token=store::native_id(reader.store(),"reader-continuation")?;
            let mut issued=outcome(reader.store(),&request.scope,PolicyKind::Renew,&request.original_attempt_id,fp.clone(),PolicyOutcomeStatus::Issued,Some(&root))?;
            issued.continuation_token=Some(token.clone());issued.valid_for_ms=Some(2000);issued.issued_at_ms=Some(now);issued.handoff=Some(PolicyHandoffState::Pending);
            attempt.renew_fingerprint=Some(fp.clone());attempt.observation_id=Some(request.observation_id.clone());attempt.outcome=issued.clone();
            store::save_root(reader.store(),&root)?;store::save_attempt(reader.store(),&attempt,"issued")?;
            let source_tail=reader.store().finish_document_source_mutation_in_transaction(&tx,plan)?;
            validate_root(reader.store(),&tx,&root,true)?;
            store::assert_root(reader.store(),&root,false)?;store::assert_attempt(reader.store(),&attempt)?;
            reader.store().verify_document_source_mutation_in_transaction(&tx,&source_tail)?;
            if started.elapsed()>FRESH{return Err(ContractError::Cancelled);}
            let handoff_started=Instant::now();
            tx.commit().map_err(|_|ContractError::Unknown)?;
            self.freshness.insert(token,handoff_started);
            Ok((previous,issued))
        })();
        let result=match ticket_and_result{
            Ok((previous,issued))=>{
                if reader.policy_suspend(&previous).is_err(){
                    // Grant issuance already committed; never report it as
                    // not-committed or automatically issue another child.
                    self.uncertain.insert(k.clone());return Err(ContractError::Unknown);
                }
                Ok(issued)
            },Err(error)=>Err(error),
        };
        self.track(k,result)
    }
    pub fn selection_changed(&mut self,reader:&mut DocumentReaderHost,scope:&PolicyScope,native_epoch:&Revision)->PolicyResult<()> {
        self.ready(reader)?;scope_shape(scope)?;if native_epoch.value()==0{return Err(ContractError::InvalidRevision);}
        if self.selection.as_ref()==Some(&(scope.clone(),native_epoch.clone())){return Ok(());}
        if self.selection.as_ref().is_some_and(|(_,old)|native_epoch<=old){return Err(ContractError::Cancelled);}
        let tx=sql(reader.store().database().transaction())?;
        let roots=store::roots(reader.store())?;let mut closing=Vec::new();
        for (root,terminal) in roots {if !terminal && root.instance==self.instance{store::fence_root(reader.store(),&root.id)?;closing.push(root.id);}}
        for id in &closing {if !store::root(reader.store(),id)?.1{return Err(ContractError::StorageCorrupt);}}
        tx.commit().map_err(|_|ContractError::Unknown)?;
        reader.policy_select(&self.instance,&store::scope_key(scope)?,native_epoch).map_err(read_error)?;
        self.selection=Some((scope.clone(),native_epoch.clone()));self.freshness.clear();
        for id in closing {if let Some(ticket)=self.tickets.get(&id).cloned(){reader.close_presentation(&ticket).map_err(read_error)?;self.tickets.remove(&id);}}
        Ok(())
    }
    pub fn frame_advanced(&mut self,reader:&mut DocumentReaderHost,previous:&PresentationTicket,next:&PresentationTicket)->PolicyResult<()> {
        self.ready(reader)?;
        let root_id=self.tickets.iter().find(|(_,ticket)|ticket.session_id()==previous.session_id()&&ticket.document()==previous.document()&&ticket.generation()==previous.generation()).map(|(id,_)|id.clone()).ok_or(ContractError::InvalidAuthority)?;
        let (mut root,terminal)=store::root(reader.store(),&root_id)?;
        if terminal || root.pending_renew.is_some() || previous.session_id()!=next.session_id() || previous.document()!=next.document() || previous.generation().next()?!=*next.generation(){return Err(ContractError::InvalidAuthority);}
        self.selected(&root.scope,&root.selection_epoch)?;
        let result=(||{
            let tx=sql(reader.store().database().transaction())?;
            validate_root(reader.store(),&tx,&root,true)?;
            reader.policy_validate_begin(&tx,next,&root.current.access,&root.metadata)?;
            root.frame=next.generation().clone();
            store::save_root(reader.store(),&root)?;
            sql(reader.store().database().exec("UPDATE document_reading_policy_attempts_v1 SET fence=1 WHERE root_id=? AND stage='prepared'",&[&root.id]))?;
            validate_root(reader.store(),&tx,&root,true)?;store::assert_root(reader.store(),&root,false)?;
            tx.commit().map_err(|_|ContractError::Unknown)
        })();
        if result.is_err(){
            let cleanup=(||{let tx=sql(reader.store().database().transaction())?;store::fence_root(reader.store(),&root.id)?;tx.commit().map_err(|_|ContractError::Unknown)})();
            let close=reader.close_presentation(next).map_err(read_error);
            if cleanup.is_err()||close.is_err(){return Err(ContractError::Unknown);}return result;
        }
        self.tickets.insert(root.id,next.clone());Ok(())
    }
}
/// Existing explicit Reader close/failure must fence the recorded root chain.
/// Natural lease/grant expiry and controlled handoff do not call this hook.
pub(super) fn fence_closed_presentation(store:&BusinessStore,ticket:&PresentationTicket)->PolicyResult<()> {
    let present=sql(store.database().query("SELECT name FROM sqlite_master WHERE name='document_reading_policy_roots_v1'",&[]))?;
    if present.is_empty(){return Ok(());}
    let tx=sql(store.database().transaction())?;store::schema(store)?;
    for (root,terminal) in store::roots(store)?{if !terminal&&root.core_session_id==ticket.session_id()&&root.frame==*ticket.generation()&&root.metadata.document==*ticket.document(){store::fence_root(store,&root.id)?;}}
    tx.commit().map_err(|_|ContractError::Unknown)
}
