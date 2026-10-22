//! Replaceable synthetic lab protocol, deliberately independent of formal M03.
mod sqlite;
mod facts;
use facts::Facts;
use rd_p01_domain_experiment::{edit_candidate,ProvisionalSnapshot};
use serde::{Deserialize,Serialize};
use serde_json::{json,Value};
use sha2::{Digest,Sha256};
use sqlite::{Db,Result};
use std::{io::Write,path::Path,os::unix::fs::OpenOptionsExt};
const APP_ID:&str="1380208695";
const FORMAT:&str="rd-p07-local-v1";
#[derive(Clone,Deserialize,Serialize,PartialEq,Debug)]
#[serde(deny_unknown_fields)]
struct Binding {
    domain:String,scope:String,supplier:String,intent:String,operation:String,
    raw_utf16:Vec<u16>,expected_revision:String,plan:String,candidate:String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Read {domain:String,scope:String,supplier:String}
enum Request {Init(Read),Read(Read),Preview(Binding),Commit(Binding),Lookup(Binding)}
fn request(text:&str)->Result<Request> {
    // serde Value alone would accept duplicate object keys. First deserialize an envelope
    // with a visitor that rejects duplicate keys in the accepted flat request object.
    let mut de=serde_json::Deserializer::from_str(text);
    let Value::Object(mut map)=Unique::deserialize(&mut de).map_err(|e|e.to_string())?.0 else {return Err("request must be object".into())};
    de.end().map_err(|e|e.to_string())?;
    let op=map.remove("op").and_then(|v|v.as_str().map(str::to_owned)).ok_or("op required")?;
    let rest=Value::Object(map);
    match op.as_str() {
        "init"=>Ok(Request::Init(serde_json::from_value(rest).map_err(|e|e.to_string())?)),
        "read"=>Ok(Request::Read(serde_json::from_value(rest).map_err(|e|e.to_string())?)),
        "preview"|"commit"|"lookup"=> {
            let b:Binding=serde_json::from_value(rest).map_err(|e|e.to_string())?;
            revision(&b.expected_revision)?;
            if [&b.domain,&b.scope,&b.supplier,&b.intent,&b.operation,&b.plan,&b.candidate].iter().any(|s|s.is_empty()) {return Err("empty binding identity".into());}
            Ok(match op.as_str() {"preview"=>Request::Preview(b),"commit"=>Request::Commit(b),_=>Request::Lookup(b)})
        },_=>Err("unsupported operation".into()),
    }
}
struct Unique(Value);
impl<'de> Deserialize<'de> for Unique {
    fn deserialize<D:serde::Deserializer<'de>>(d:D)->std::result::Result<Self,D::Error> {
        struct Visitor;
        impl<'de> serde::de::Visitor<'de> for Visitor {
            type Value=Unique;
            fn expecting(&self,f:&mut std::fmt::Formatter)->std::fmt::Result {f.write_str("unique-key object")}
            fn visit_map<M:serde::de::MapAccess<'de>>(self,mut m:M)->std::result::Result<Unique,M::Error> {
                let mut out=serde_json::Map::new();
                while let Some(k)=m.next_key::<String>()? {if out.contains_key(&k) {return Err(serde::de::Error::custom("duplicate key"));}out.insert(k,m.next_value::<Value>()?);}
                Ok(Unique(Value::Object(out)))
            }
        }
        d.deserialize_map(Visitor)
    }
}
fn revision(s:&str)->Result<u64> {
    let n=s.parse::<u64>().map_err(|_|"revision must be canonical u64 decimal")?;
    if n==0 || n.to_string()!=s {return Err("revision must be positive canonical u64 decimal".into());} Ok(n)
}
fn cell(row:&[Option<String>],n:usize)->Result<&str> {row.get(n).and_then(Option::as_deref).ok_or_else(||"missing/non-text database value".into())}
fn scalar(db:&Db,sql:&str)->Result<String> {let rows=db.query(sql,&[])?;if rows.len()!=1 {return Err("expected scalar".into());}Ok(cell(&rows[0],0)?.into())}
fn validate(db:&Db)->Result<String> {
    if scalar(db,"PRAGMA application_id")?!=APP_ID || scalar(db,"PRAGMA user_version")?!="1" {return Err("incompatible lab database".into());}
    let expected=[("meta",vec!["domain","format"]),("suppliers",vec!["id","scope","name","revision","untouched"]),("intents",vec!["intent","binding","status","rejection"]),("history",vec!["intent","supplier","old_name","new_name","old_revision","new_revision","binding"]),("receipts",vec!["intent","body"])];
    for (table,columns) in expected {
        let rows=db.query(&format!("PRAGMA table_info({table})"),&[])?;
        if rows.len()!=columns.len() {return Err("incompatible table shape".into());}
        for (i,(r,c)) in rows.iter().zip(columns).enumerate() {
            let pk=if i==0 {"1"} else {"0"};
            let not_null=if i==0 || (table=="intents" && c=="rejection") {"0"} else {"1"};
            if cell(r,1)?!=c || cell(r,2)?!="TEXT" || cell(r,3)?!=not_null || cell(r,5)?!=pk {return Err("incompatible table type/constraints".into());}
        }
    }
    let meta=db.query("SELECT domain,format FROM meta",&[])?;
    if meta.len()!=1 || cell(&meta[0],1)?!=FORMAT {return Err("incompatible domain format".into());}
    for r in db.query("SELECT revision,typeof(revision) FROM suppliers",&[])? {revision(cell(&r,0)?)?;if cell(&r,1)?!="text" {return Err("revision affinity error".into());}}
    Ok(cell(&meta[0],0)?.into())
}
fn snapshot(db:&Db,domain:&str,r:&Read)->Result<ProvisionalSnapshot> {
    if domain!=r.domain {return Err("domain mismatch".into());}
    let rows=db.query("SELECT scope,name,revision FROM suppliers WHERE id=?",&[&r.supplier])?;
    if rows.len()!=1 || cell(&rows[0],0)?!=r.scope {return Err("supplier unavailable in scope".into());}
    Ok(ProvisionalSnapshot {scope:r.scope.clone(),supplier_id:r.supplier.clone(),name:cell(&rows[0],1)?.into(),revision:revision(cell(&rows[0],2)?)?,deleted:false})
}
fn read_binding(b:&Binding)->Read {Read {domain:b.domain.clone(),scope:b.scope.clone(),supplier:b.supplier.clone()}}
fn serialized(b:&Binding)->Result<String> {serde_json::to_string(b).map_err(|e|e.to_string())}
fn hex(bytes:&[u8])->String {bytes.iter().map(|b|format!("{b:02x}")).collect()}
fn digest(text:&str)->String {hex(&Sha256::digest(text.as_bytes()))}
fn receipt(b:&Binding,old:&str,new:&str,old_rev:&str,new_rev:&str)->Result<Value> {
    Ok(json!({"intent":b.intent,"binding":b,"binding_sha256":digest(&serialized(b)?),"source":b.domain,"supplier":b.supplier,"old_name":old,"new_name":new,"old_revision":old_rev,"new_revision":new_rev}))
}
fn verified(db:&Db,b:&Binding)->Result<Option<Value>> {
    let rows=db.query("SELECT h.supplier,h.old_name,h.new_name,h.old_revision,h.new_revision,h.binding,r.body FROM history h JOIN receipts r ON r.intent=h.intent WHERE h.intent=?",&[&b.intent])?;
    if rows.is_empty() {return Ok(None);} if rows.len()!=1 {return Err("receipt multiplicity".into());}
    let r=&rows[0];
    let original:Binding=serde_json::from_str(cell(r,5)?).map_err(|_|"invalid history binding")?;
    if original!=*b || cell(r,0)?!=b.supplier {return Err("receipt/history binding mismatch".into());}
    let old=revision(cell(r,3)?)?;let new=revision(cell(r,4)?)?;
    let normalized=rd_p01_domain_experiment::normalize_raw(&b.raw_utf16).map_err(|_|"invalid receipt arguments")?;
    if cell(r,3)?!=b.expected_revision || old.checked_add(1)!=Some(new) || cell(r,2)?!=normalized {return Err("invalid history effect".into());}
    let expected=receipt(b,cell(r,1)?,cell(r,2)?,cell(r,3)?,cell(r,4)?)?;
    let actual:Value=serde_json::from_str(cell(r,6)?).map_err(|_|"invalid receipt JSON")?;
    if actual!=expected {return Err("receipt mismatch".into());} Ok(Some(actual))
}
fn existing(db:&Db,domain:&str,b:&Binding)->Result<Option<Value>> {
    let rows=db.query("SELECT binding,status,rejection FROM intents WHERE intent=?",&[&b.intent])?;
    if rows.is_empty() {return Ok(None);} if rows.len()!=1 {return Err("intent multiplicity".into());}
    let original:Binding=serde_json::from_str(cell(&rows[0],0)?).map_err(|_|"invalid intent binding")?;
    if original!=*b {return Ok(Some(json!({"status":"conflict"})));} // MUTATION_BINDING
    if original.domain!=domain {return Err("stored intent domain does not match physical database".into());}
    let result=match cell(&rows[0],1)? {
        "committed"=>match verified(db,b)? {Some(r)=>json!({"status":"committed","receipt":r}),None=>json!({"status":"unknown"})},
        "pending"=>json!({"status":"unknown"}), // MUTATION_UNKNOWN
        "rejected"=>json!({"status":"rejected","reason":cell(&rows[0],2)?}),
        _=>return Err("invalid intent status".into()),
    }; Ok(Some(result))
}
fn fault(control:&Option<String>,stage:&str) {
    match control.as_deref() {
        Some(s) if s==format!("exit:{stage}")=>std::process::exit(86),
        Some(s) if s==format!("barrier:{stage}")=>{println!("BARRIER {stage}");std::io::stdout().flush().unwrap();loop {std::thread::park();}},
        _=>{},
    }
}
fn commit(db:&Db,domain:&str,b:&Binding,control:&Option<String>)->Result<Value> {
    let binding=serialized(b)?;
    {
        let claim=db.transaction()?;
        if validate(db)?!=domain {return Err("database identity changed".into());}
        if let Some(result)=existing(db,domain,b)? {return Ok(result);} // MUTATION_DUPLICATE
        if b.domain!=domain {return Err("domain mismatch".into());}
        let mut claim_facts=Facts::capture(db)?;
        claim_facts.add_pending(&b.intent,&binding);
        if db.exec("INSERT INTO intents(intent,binding,status) VALUES(?,?,'pending')",&[&b.intent,&binding])?!=1 {return Err("pending claim failed".into());}
        claim_facts.verify(db,"pending phase")?;
        claim.commit()?;
    }
    fault(control,"pending");
    let tx=db.transaction()?; // MUTATION_TRANSACTION
    if validate(db)?!=domain {return Err("database identity changed".into());}
    let mut effect_facts=Facts::capture(db)?;
    let snap=snapshot(db,domain,&read_binding(b))?;
    let candidate=if b.operation!="supplier.name" {Err("Operation".to_owned())} else {edit_candidate(&snap,&b.scope,&b.supplier,revision(&b.expected_revision)?,&b.raw_utf16).map_err(|e|format!("{e:?}"))};
    let c=match candidate {Ok(c)=>c,Err(reason)=> {
        effect_facts.finish_intent(&b.intent,&binding,"rejected",Some(&reason))?;
        if db.exec("UPDATE intents SET status='rejected',rejection=? WHERE intent=? AND status='pending' AND binding=?",&[&reason,&b.intent,&binding])?!=1 {return Err("rejection ownership lost".into());}
        effect_facts.verify(db,"rejection phase")?;
        tx.commit()?;return Ok(json!({"status":"rejected","reason":reason}));
    }};
    let next=c.candidate_revision.to_string();
    let changed=db.exec("UPDATE suppliers SET name=?,revision=? WHERE id=? AND scope=? AND revision=?",&[&c.normalized_name,&next,&b.supplier,&b.scope,&b.expected_revision])?; // MUTATION_CAS
    if changed!=1 {return Err("guarded update affected row mismatch".into());}
    fault(control,"update");
    let actual=db.query("SELECT name,revision FROM suppliers WHERE id=? AND scope=?",&[&b.supplier,&b.scope])?;
    if actual.len()!=1 || cell(&actual[0],0)?!=c.normalized_name || cell(&actual[0],1)?!=next {return Err("actual effect mismatch".into());}
    if db.exec("INSERT INTO history VALUES(?,?,?,?,?,?,?)",&[&b.intent,&b.supplier,&snap.name,cell(&actual[0],0)?,&b.expected_revision,cell(&actual[0],1)?,&binding])?!=1 {return Err("history insert failed".into());}
    fault(control,"history");
    if db.exec("UPDATE intents SET status='committed' WHERE intent=? AND binding=? AND status='pending'",&[&b.intent,&binding])?!=1 {return Err("intent ownership lost".into());}
    fault(control,"intent");
    let effect=db.query("SELECT new_name,new_revision FROM history WHERE intent=?",&[&b.intent])?;
    if effect.len()!=1 {return Err("effect missing".into());}
    let r=receipt(b,&snap.name,cell(&effect[0],0)?,&b.expected_revision,cell(&effect[0],1)?)?;
    let body=serde_json::to_string(&r).map_err(|e|e.to_string())?;
    if db.exec("INSERT INTO receipts VALUES(?,?)",&[&b.intent,&body])?!=1 {return Err("receipt insert failed".into());}
    fault(control,"receipt");
    // Check the four final facts after all SQL/fixture-trigger work, inside this
    // transaction. Also prove that the target's other fields and other rows survive.
    let mut target_found=false;
    for row in &mut effect_facts.suppliers {
        if cell(row,0)?==b.supplier {
            row[2]=Some(c.normalized_name.clone()); row[3]=Some(next.clone()); target_found=true;
        }
    }
    effect_facts.finish_intent(&b.intent,&binding,"committed",None)?;
    effect_facts.history.push(vec![Some(b.intent.clone()),Some(b.supplier.clone()),Some(snap.name.clone()),Some(c.normalized_name.clone()),Some(b.expected_revision.clone()),Some(next.clone()),Some(binding.clone())]);
    effect_facts.history.sort();
    effect_facts.receipts.push(vec![Some(b.intent.clone()),Some(body)]);
    effect_facts.receipts.sort();
    let final_fact=existing(db,domain,b).map_err(|e|format!("final consistency: {e}"))?;
    let expected_fact=json!({"status":"committed","receipt":r});
    if !target_found || final_fact!=Some(expected_fact) || validate(db)?!=domain {return Err("final consistency mismatch".into());}
    effect_facts.verify(db,"final")?;
    tx.commit()?; fault(control,"commit");
    Ok(json!({"status":"committed","receipt":r}))
}
fn initialize(path:&str,r:&Read)->Result<Value> {
    if Path::new(path).exists() {return Err("init refuses existing path".into());}
    if r.domain.is_empty() || r.scope.is_empty() || r.supplier!="S1" {return Err("init requires synthetic fixture S1".into());}
    // Reserve a private new file exclusively; explicit init is the only create path.
    let _file=std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(path).map_err(|e|e.to_string())?;
    let db=Db::open(path,false,false)?;
    db.query("PRAGMA journal_mode=DELETE",&[])?;
    db.exec("PRAGMA synchronous=FULL",&[])?;
    let tx=db.transaction()?;
    for sql in ["PRAGMA application_id=1380208695","PRAGMA user_version=1","CREATE TABLE meta(domain TEXT PRIMARY KEY, format TEXT NOT NULL)","CREATE TABLE suppliers(id TEXT PRIMARY KEY, scope TEXT NOT NULL, name TEXT NOT NULL, revision TEXT NOT NULL, untouched TEXT NOT NULL)","CREATE TABLE intents(intent TEXT PRIMARY KEY, binding TEXT NOT NULL, status TEXT NOT NULL, rejection TEXT)","CREATE TABLE history(intent TEXT PRIMARY KEY, supplier TEXT NOT NULL, old_name TEXT NOT NULL, new_name TEXT NOT NULL, old_revision TEXT NOT NULL, new_revision TEXT NOT NULL, binding TEXT NOT NULL)","CREATE TABLE receipts(intent TEXT PRIMARY KEY, body TEXT NOT NULL)"] {db.exec(sql,&[])?;}
    db.exec("INSERT INTO meta VALUES(?,?)",&[&r.domain,FORMAT])?;
    for (id,other) in [("S1","keep-one"),("S2","keep-two")] {db.exec("INSERT INTO suppliers VALUES(?,?,'Before','1',?)",&[id,&r.scope,other])?;}
    tx.commit()?; Ok(json!({"status":"initialized","runtime":runtime()?}))
}
fn runtime()->Result<Value> {
    let maps=std::fs::read_to_string("/proc/self/maps").map_err(|e|e.to_string())?;
    let path=maps.lines().filter_map(|line|line.split_whitespace().last()).find(|p|p.contains("/libsqlite3.so.")).ok_or("SQLite runtime mapping unavailable")?;
    let bytes=std::fs::read(path).map_err(|e|e.to_string())?;
    Ok(json!({"path":path,"version":sqlite::version(),"sha256":hex(&Sha256::digest(bytes))}))
}
fn run()->Result<Value> {
    let mut args=std::env::args().skip(1);let mut path=None;let mut text=None;let mut control=None;
    while let Some(arg)=args.next() {
        let value=args.next().ok_or("flag without value")?;
        match arg.as_str() {"--db" if path.is_none()=>path=Some(value),"--request" if text.is_none()=>text=Some(value),"--fault" if control.is_none()=>control=Some(value),_=>return Err("unknown or duplicate flag".into())}
    }
    if let Some(s)=&control {let Some((mode,stage))=s.split_once(':') else {return Err("invalid fault".into())};if !["exit","barrier"].contains(&mode) || !["pending","update","history","intent","receipt","commit"].contains(&stage) {return Err("invalid fault".into());}}
    let path=path.ok_or("--db required")?;let r=request(&text.ok_or("--request required")?)?;
    if control.is_some() && !matches!(&r,Request::Commit(_)) {return Err("fault only allowed for commit".into());}
    if let Request::Init(r)=r {return initialize(&path,&r);}
    let writable=matches!(&r,Request::Commit(_));let db=Db::open(&path,!writable,false)?;
    if writable {db.exec("PRAGMA synchronous=FULL",&[])?;}
    // One consistent read snapshot prevents lookup joins/identity drifting between queries.
    let read_tx=if !writable {db.exec("BEGIN",&[])?;true} else {false};
    let domain=validate(&db)?;
    let out=match r {
        Request::Read(r)=>{let s=snapshot(&db,&domain,&r)?;json!({"status":"read","supplier":{"id":s.supplier_id,"name":s.name,"revision":s.revision.to_string()}})},
        Request::Preview(b)=>{let s=snapshot(&db,&domain,&read_binding(&b))?;if b.operation!="supplier.name" {json!({"status":"rejected","reason":"Operation"})} else {match edit_candidate(&s,&b.scope,&b.supplier,revision(&b.expected_revision)?,&b.raw_utf16) {Ok(c)=>json!({"status":"preview","normalized_name":c.normalized_name,"candidate_revision":c.candidate_revision.to_string()}),Err(e)=>json!({"status":"rejected","reason":format!("{e:?}")})}}},
        Request::Commit(b)=>commit(&db,&domain,&b,&control)?,
        Request::Lookup(b)=>{if let Some(result)=existing(&db,&domain,&b)? {result} else {if b.domain!=domain {return Err("domain mismatch".into());}json!({"status":"unknown","receipt_found":false})}},
        Request::Init(_)=>unreachable!(),
    };
    if read_tx {db.exec("COMMIT",&[])?;} Ok(out)
}
fn main() {match run() {Ok(v)=>println!("{v}"),Err(e)=>{eprintln!("unavailable: {e}");std::process::exit(2);}}}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn canonical_revision(){assert_eq!(revision("9007199254740993"),Ok(9007199254740993));for s in ["0","01","1.0","18446744073709551616"] {assert!(revision(s).is_err());}}
    #[test] fn strict_duplicate_key(){assert!(request(r#"{"op":"read","op":"init","domain":"A","scope":"S","supplier":"S1"}"#).is_err());}
}
