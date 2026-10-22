//! Policy ledger on the existing owner connection. No second store or path.
use super::*;
use crate::{business::BusinessStore, sqlite::Transaction};
const ROOTS: &str = "document_reading_policy_roots_v1";
const ATTEMPTS: &str = "document_reading_policy_attempts_v1";
const ROOT_DDL: &str = "CREATE TABLE document_reading_policy_roots_v1(root_id TEXT PRIMARY KEY,instance_id TEXT NOT NULL,owner_epoch TEXT NOT NULL,scope_key TEXT NOT NULL,project_id TEXT NOT NULL,document_id TEXT NOT NULL,document_revision TEXT NOT NULL,source_digest TEXT NOT NULL,parent_id TEXT NOT NULL,parent_generation TEXT NOT NULL,child_id TEXT NOT NULL,child_generation TEXT NOT NULL,terminal INTEGER NOT NULL CHECK(terminal IN(0,1)),renewing INTEGER NOT NULL CHECK(renewing IN(0,1)),payload TEXT NOT NULL)";
const ATTEMPT_DDL: &str = "CREATE TABLE document_reading_policy_attempts_v1(scope_key TEXT NOT NULL,kind TEXT NOT NULL,attempt_id TEXT NOT NULL,root_id TEXT NOT NULL,fingerprint TEXT NOT NULL,stage TEXT NOT NULL,fence INTEGER NOT NULL CHECK(fence IN(0,1)),observation_id TEXT UNIQUE,payload TEXT NOT NULL,PRIMARY KEY(scope_key,kind,attempt_id))";
const TRIGGERS: &[(&str, &str)] = &[
("document_reading_policy_terminal_v1", "CREATE TRIGGER document_reading_policy_terminal_v1 AFTER UPDATE OF terminal ON document_reading_policy_roots_v1 WHEN NEW.terminal=1 AND OLD.terminal=0 BEGIN UPDATE document_grants SET active=0 WHERE grant_id=NEW.child_id AND generation=NEW.child_generation; UPDATE document_reading_policy_attempts_v1 SET fence=1 WHERE root_id=NEW.root_id; END"),
("document_reading_policy_no_unfence_v1", "CREATE TRIGGER document_reading_policy_no_unfence_v1 BEFORE UPDATE OF terminal ON document_reading_policy_roots_v1 WHEN OLD.terminal=1 AND NEW.terminal=0 BEGIN SELECT RAISE(ABORT,'reader root terminal'); END"),
("document_reading_policy_grant_v1", "CREATE TRIGGER document_reading_policy_grant_v1 AFTER UPDATE ON document_grants WHEN NEW.active=0 OR NEW.generation<>OLD.generation OR NEW.owner_epoch<>OLD.owner_epoch OR NEW.document_json<>OLD.document_json OR NEW.permissions<>OLD.permissions BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE (parent_id=OLD.grant_id AND parent_generation=OLD.generation) OR (child_id=OLD.grant_id AND child_generation=OLD.generation AND renewing=0); END"),
("document_reading_policy_grant_delete_v1", "CREATE TRIGGER document_reading_policy_grant_delete_v1 AFTER DELETE ON document_grants BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE (parent_id=OLD.grant_id AND parent_generation=OLD.generation) OR (child_id=OLD.grant_id AND child_generation=OLD.generation); END"),
("document_reading_policy_head_v1", "CREATE TRIGGER document_reading_policy_head_v1 AFTER UPDATE ON document_heads WHEN NEW.revision<>OLD.revision OR NEW.project_id<>OLD.project_id OR NEW.document_id<>OLD.document_id BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.project_id AND document_id=OLD.document_id; END"),
("document_reading_policy_head_delete_v1", "CREATE TRIGGER document_reading_policy_head_delete_v1 AFTER DELETE ON document_heads BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.project_id AND document_id=OLD.document_id; END"),
("document_reading_policy_source_v1", "CREATE TRIGGER document_reading_policy_source_v1 AFTER UPDATE ON document_revisions WHEN NEW.payload<>OLD.payload OR NEW.revision<>OLD.revision OR NEW.project_id<>OLD.project_id OR NEW.document_id<>OLD.document_id BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.project_id AND document_id=OLD.document_id AND document_revision=OLD.revision; END"),
("document_reading_policy_source_delete_v1", "CREATE TRIGGER document_reading_policy_source_delete_v1 AFTER DELETE ON document_revisions BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.project_id AND document_id=OLD.document_id AND document_revision=OLD.revision; END"),
("document_reading_policy_project_v1", "CREATE TRIGGER document_reading_policy_project_v1 AFTER UPDATE ON projects WHEN NEW.deleted<>0 OR NEW.revision<>OLD.revision OR NEW.workspace<>OLD.workspace BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.id; END"),
("document_reading_policy_project_delete_v1", "CREATE TRIGGER document_reading_policy_project_delete_v1 AFTER DELETE ON projects BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE project_id=OLD.id; END"),
("document_reading_policy_blob_v1", "CREATE TRIGGER document_reading_policy_blob_v1 AFTER UPDATE ON blobs WHEN NEW.state<>'ready' OR NEW.byte_length<>OLD.byte_length OR NEW.digest<>OLD.digest BEGIN UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE source_digest=OLD.digest; END"),
];
fn cell(row: &[Option<String>], n: usize) -> PolicyResult<&str> { row.get(n).and_then(Option::as_deref).ok_or(ContractError::StorageCorrupt) }
pub(super) fn json<T: Serialize>(value: &T) -> PolicyResult<String> { let value=serde_json::to_string(value).map_err(|_| ContractError::InvalidPayload)?; if value.len()>16384 { return Err(ContractError::TextLimit); } Ok(value) }
fn decode<T: serde::de::DeserializeOwned>(text: &str) -> PolicyResult<T> { serde_json::from_str(text).map_err(|_| ContractError::StorageCorrupt) }
pub(super) fn scope_key(scope: &PolicyScope) -> PolicyResult<String> { scope_shape(scope)?; Ok(hash(&json(scope)?)) }
fn kind(kind: PolicyKind) -> &'static str { match kind { PolicyKind::Begin=>"begin", PolicyKind::Renew|PolicyKind::Handoff=>"renew", PolicyKind::Stop=>"stop" } }
pub(super) fn initialize(store: &BusinessStore) -> PolicyResult<()> {
    let tx=sql(store.database().transaction())?;
    let rows=sql(store.database().query("SELECT name FROM sqlite_master WHERE name LIKE 'document_reading_policy_%'",&[]))?;
    if rows.is_empty() {
        sql(store.database().exec(ROOT_DDL,&[]))?; sql(store.database().exec(ATTEMPT_DDL,&[]))?;
        for (_, ddl) in TRIGGERS { sql(store.database().exec(ddl,&[]))?; }
    }
    schema(store)?;
    // Fresh native owner instance: old live roots never survive a new open,
    // even if the caller accidentally reused its textual owner epoch.
    sql(store.database().exec("UPDATE document_reading_policy_roots_v1 SET terminal=1 WHERE terminal=0",&[]))?;
    let remaining=sql(store.database().query("SELECT 1 FROM document_reading_policy_roots_v1 WHERE terminal<>1 OR renewing<>0",&[]))?;
    if !remaining.is_empty() { return Err(ContractError::StorageCorrupt); }
    tx.commit().map_err(|_|ContractError::Unknown)
}
pub(super) fn schema(store: &BusinessStore) -> PolicyResult<()> {
    let mut expected=vec![(ROOTS,ROOT_DDL,"table"),(ATTEMPTS,ATTEMPT_DDL,"table")];
    expected.extend(TRIGGERS.iter().map(|(name,ddl)|(*name,*ddl,"trigger")));
    let rows=sql(store.database().query("SELECT name,type,CASE WHEN length(CAST(sql AS BLOB))<=8192 THEN sql ELSE NULL END FROM sqlite_master WHERE name LIKE 'document_reading_policy_%' ORDER BY name",&[]))?;
    if rows.len()!=expected.len() { return Err(ContractError::InvalidVersion); }
    for row in rows { let name=cell(&row,0)?; let wanted=expected.iter().find(|(n,_,_)|*n==name).ok_or(ContractError::InvalidVersion)?; if cell(&row,1)?!=wanted.2 || cell(&row,2)?!=wanted.1 { return Err(ContractError::InvalidVersion); } }
    let counts=sql(store.database().query("SELECT (SELECT COUNT(*) FROM document_reading_policy_roots_v1),(SELECT COUNT(*) FROM document_reading_policy_attempts_v1)",&[]))?;
    let roots=cell(&counts[0],0)?.parse::<usize>().map_err(|_|ContractError::StorageCorrupt)?;let attempts=cell(&counts[0],1)?.parse::<usize>().map_err(|_|ContractError::StorageCorrupt)?;
    if roots>MAX_POLICY_ROOTS || attempts>MAX_POLICY_ATTEMPTS { return Err(ContractError::StorageCorrupt); }
    Ok(())
}
pub(super) fn native_id(store: &BusinessStore, prefix: &str) -> PolicyResult<String> { let rows=sql(store.database().query("SELECT lower(hex(randomblob(16)))",&[]))?;let id=format!("{prefix}-{}",cell(&rows[0],0)?);id_shape(&id)?;Ok(id) }
pub(super) fn root(store: &BusinessStore, id: &str) -> PolicyResult<(RootRecord,bool)> {
    id_shape(id)?; schema(store)?;
    let rows=sql(store.database().query("SELECT CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload ELSE NULL END,terminal,renewing FROM document_reading_policy_roots_v1 WHERE root_id=?",&[id]))?;
    let row=rows.first().ok_or(ContractError::NotFound)?; let value:RootRecord=decode(cell(row,0)?)?;
    scope_shape(&value.scope)?; surface_shape(&value.surface)?; value.metadata.blob.validate()?;
    if value.id!=id || value.metadata.document.scope().workspace_id!=store.workspace_id() || value.metadata.document.scope().project_id.as_deref()!=Some(value.scope.project.as_str()) || value.revision.value()==0 || value.readonly_operations.is_empty() || value.readonly_operations.len()>3 || !value.readonly_operations.contains(&DocumentOperation::Render) || value.readonly_operations.iter().any(|op|!op.is_read()) { return Err(ContractError::StorageCorrupt); }
    let child=value.child_id.as_deref().unwrap_or("");let generation=if value.child_id.is_some(){value.current.access.authority.generation.as_str()}else{""};
    let exact=sql(store.database().query("SELECT 1 FROM document_reading_policy_roots_v1 WHERE root_id=? AND instance_id=? AND owner_epoch=? AND scope_key=? AND project_id=? AND document_id=? AND document_revision=? AND source_digest=? AND parent_id=? AND parent_generation=? AND child_id=? AND child_generation=?",&[id,&value.instance,&value.owner_epoch,&scope_key(&value.scope)?,&value.scope.project,value.metadata.document.document_id(),value.metadata.document.revision().as_str(),&value.metadata.blob.digest,&value.parent.access.authority.grant_id,value.parent.access.authority.generation.as_str(),child,generation]))?;
    if exact.len()!=1 || cell(row,2)?!="0" { return Err(ContractError::StorageCorrupt); }
    let terminal=match cell(row,1)?{"0"=>false,"1"=>true,_=>return Err(ContractError::StorageCorrupt)};Ok((value,terminal))
}
pub(super) fn roots(store: &BusinessStore) -> PolicyResult<Vec<(RootRecord,bool)>> { schema(store)?;let rows=sql(store.database().query("SELECT CASE WHEN length(CAST(root_id AS BLOB))<=128 THEN root_id ELSE NULL END FROM document_reading_policy_roots_v1 ORDER BY root_id LIMIT 17",&[]))?;if rows.len()>MAX_POLICY_ROOTS{return Err(ContractError::StorageCorrupt);}rows.iter().map(|r|root(store,cell(r,0)?)).collect() }
pub(super) fn insert_root(store:&BusinessStore,value:&RootRecord)->PolicyResult<()> {
    if roots(store)?.len()>=MAX_POLICY_ROOTS{return Err(ContractError::TextLimit);}
    sql(store.database().exec("INSERT INTO document_reading_policy_roots_v1 VALUES(?,?,?,?,?,?,?,?,?,?,?, ?,0,0,?)",&[&value.id,&value.instance,&value.owner_epoch,&scope_key(&value.scope)?,&value.scope.project,value.metadata.document.document_id(),value.metadata.document.revision().as_str(),&value.metadata.blob.digest,&value.parent.access.authority.grant_id,value.parent.access.authority.generation.as_str(),"","",&json(value)?]))?;Ok(())
}
pub(super) fn save_root(store:&BusinessStore,value:&RootRecord)->PolicyResult<()> {
    let child=value.child_id.as_deref().unwrap_or("");let generation=if value.child_id.is_some(){value.current.access.authority.generation.as_str()}else{""};
    let changed=sql(store.database().exec("UPDATE document_reading_policy_roots_v1 SET child_id=?,child_generation=?,payload=?,renewing=0 WHERE root_id=? AND terminal=0",&[child,generation,&json(value)?,&value.id]))?;if changed!=1{return Err(ContractError::Cancelled);}Ok(())
}
pub(super) fn save_terminal_root(store:&BusinessStore,value:&RootRecord)->PolicyResult<()> {let changed=sql(store.database().exec("UPDATE document_reading_policy_roots_v1 SET payload=?,terminal=1,renewing=0 WHERE root_id=?",&[&json(value)?,&value.id]))?;if changed!=1{return Err(ContractError::StorageCorrupt);}Ok(())}
pub(super) fn fence_root(store:&BusinessStore,id:&str)->PolicyResult<()> { let changed=sql(store.database().exec("UPDATE document_reading_policy_roots_v1 SET terminal=1,renewing=0 WHERE root_id=?",&[id]))?;if changed!=1{return Err(ContractError::NotFound);}Ok(()) }
pub(super) fn attempt(store:&BusinessStore,scope:&PolicyScope,k:PolicyKind,id:&str)->PolicyResult<Option<(AttemptRecord,bool)>> {
    id_shape(id)?;schema(store)?;let rows=sql(store.database().query("SELECT CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload ELSE NULL END,fence,CASE WHEN length(CAST(fingerprint AS BLOB))<=64 THEN fingerprint ELSE NULL END FROM document_reading_policy_attempts_v1 WHERE scope_key=? AND kind=? AND attempt_id=?",&[&scope_key(scope)?,kind(k),id]))?;
    if rows.is_empty(){return Ok(None);}let record:AttemptRecord=decode(cell(&rows[0],0)?)?;if record.scope!=*scope || record.id!=id || kind(record.kind)!=kind(k) || record.fingerprint!=cell(&rows[0],2)?{return Err(ContractError::StorageCorrupt);}let fence=match cell(&rows[0],1)?{"0"=>false,"1"=>true,_=>return Err(ContractError::StorageCorrupt)};Ok(Some((record,fence)))
}
pub(super) fn insert_attempt(store:&BusinessStore,value:&AttemptRecord,stage:&str)->PolicyResult<()> {
    schema(store)?;let count=sql(store.database().query("SELECT COUNT(*) FROM document_reading_policy_attempts_v1",&[]))?;if cell(&count[0],0)?.parse::<usize>().map_err(|_|ContractError::StorageCorrupt)?>=MAX_POLICY_ATTEMPTS{return Err(ContractError::TextLimit);}
    sql(store.database().exec("INSERT INTO document_reading_policy_attempts_v1 VALUES(?,?,?,?,?,?,0,NULLIF(?,''),?)",&[&scope_key(&value.scope)?,kind(value.kind),&value.id,value.root_id.as_deref().unwrap_or(""),&value.fingerprint,stage,value.observation_id.as_deref().unwrap_or(""),&json(value)?]))?;Ok(())
}
pub(super) fn save_attempt(store:&BusinessStore,value:&AttemptRecord,stage:&str)->PolicyResult<()> {
    let changed=sql(store.database().exec("UPDATE document_reading_policy_attempts_v1 SET stage=?,observation_id=NULLIF(?,''),payload=? WHERE scope_key=? AND kind=? AND attempt_id=? AND fingerprint=?",&[stage,value.observation_id.as_deref().unwrap_or(""),&json(value)?,&scope_key(&value.scope)?,kind(value.kind),&value.id,&value.fingerprint]))?;if changed!=1{return Err(ContractError::StorageCorrupt);}Ok(())
}
pub(super) fn assert_root(store:&BusinessStore,value:&RootRecord,terminal:bool)->PolicyResult<()> {let (actual,dead)=root(store,&value.id)?;if dead!=terminal || json(&actual)?!=json(value)?{return Err(ContractError::StorageCorrupt);}Ok(())}
pub(super) fn assert_attempt(store:&BusinessStore,value:&AttemptRecord)->PolicyResult<()> {let (actual,_)=attempt(store,&value.scope,value.kind,&value.id)?.ok_or(ContractError::StorageCorrupt)?;if json(&actual)?!=json(value)?{return Err(ContractError::StorageCorrupt);}Ok(())}
pub(super) fn begin_renew_guard(store:&BusinessStore,root:&RootRecord)->PolicyResult<()> {let changed=sql(store.database().exec("UPDATE document_reading_policy_roots_v1 SET renewing=1 WHERE root_id=? AND terminal=0 AND renewing=0 AND payload=?",&[&root.id,&json(root)?]))?;if changed!=1{return Err(ContractError::Cancelled);}Ok(())}
pub(super) fn issue_child(store:&BusinessStore,tx:&Transaction<'_>,root:&RootRecord,next:&GrantRecord)->PolicyResult<()> {
    if !tx.belongs_to(store.database()) || next.access.document!=root.metadata.document || next.operations!=root.readonly_operations || !next.active || next.expires_at_ms<=storage::now_ms()? || next.expires_at_ms>storage::now_ms()?.checked_add(30_000).ok_or(ContractError::InvalidAuthority)? {return Err(ContractError::InvalidAuthority);}
    let a=&next.access.authority;let document=json(&next.access.document)?;let permissions=json(&next.operations)?;
    if let Some(child)=&root.child_id {
        if child!=&a.grant_id || a.generation!=root.current.access.authority.generation.next()?{return Err(ContractError::InvalidAuthority);}
        let changed=sql(store.database().exec("UPDATE document_grants SET generation=?,expires_at_ms=? WHERE grant_id=? AND generation=? AND owner_epoch=? AND document_json=? AND permissions=? AND active=1",&[a.generation.as_str(),&next.expires_at_ms.to_string(),&a.grant_id,root.current.access.authority.generation.as_str(),store.owner_epoch(),&document,&permissions]))?;if changed!=1{return Err(ContractError::InvalidAuthority);}
    } else {
        if a.generation!=Revision::new(1) || a.grant_id==root.parent.access.authority.grant_id {return Err(ContractError::InvalidAuthority);}
        sql(store.database().exec("INSERT INTO document_grants VALUES(?,?,?,?,?,?,1)",&[&a.grant_id,a.generation.as_str(),store.owner_epoch(),&document,&permissions,&next.expires_at_ms.to_string()]))?;
    }
    Ok(())
}
