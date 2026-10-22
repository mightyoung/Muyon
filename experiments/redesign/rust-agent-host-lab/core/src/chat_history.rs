//! Trusted same-conversation raw turns. No model memory, replay or UI history input.
use crate::{field, ordinary_chat, service_host::ServiceHostPorts, service_types::*, supplier_business::{self,BusinessRead}, Json, Result};
use muyon_plugin_contract_lab::{object,string};
use std::path::Path;

pub(crate) const VERSION:&str="ordinary-context-v1";
pub(crate) const MAX_TURNS:usize=8;
pub(crate) fn failure(reason:String)->String {if reason=="chat_context_limit"{reason}else{"chat_history_unavailable".into()}}
fn closed(j:&Json,keys:&[&str])->Result<()> {
    let m=j.object()?;
    if m.len()!=keys.len() || keys.iter().any(|k|!m.contains_key(*k)){return Err("chat_history_unavailable".into())}Ok(())
}
fn text<'a>(j:&'a Json,k:&str)->Result<&'a str>{field(j,k)?.string()}
fn hex(v:&str,n:usize)->bool{v.len()==n && v.bytes().all(|c|c.is_ascii_digit()||(b'a'..=b'f').contains(&c))}
pub(crate) fn versioned(context:&Json)->Result<bool> {
    let m=context.object()?;
    let new=m.contains_key("history")||m.contains_key("history_version");
    if new {
        closed(context,&["authority","workspace","conversation","input_ref","task","attempt","input_version","history_version","history"])?;
        if text(context,"history_version")?!=VERSION{return Err("chat_history_unavailable".into())}
    }else{closed(context,&["authority","workspace","conversation","input_ref","task","attempt","input_version"])?;}
    Ok(new)
}
pub(crate) fn units(context:&Json)->Result<Vec<Json>> {
    if !versioned(context)?{return Ok(vec![])}
    let rows=field(context,"history")?.array()?;
    if rows.len()>MAX_TURNS{return Err("chat_context_limit".into())}
    let mut seen=std::collections::BTreeSet::new();
    for (index,row) in rows.iter().enumerate() {
        closed(row,&["request","run","epoch","build","task","attempt","input_ref","receipt","authority","user","answer","ancestors"])?;
        let run=text(row,"run")?;
        if !hex(run,32)||!hex(text(row,"epoch")?,32)||!hex(text(row,"build")?,40)||!seen.insert(run.to_owned()) {return Err("chat_history_unavailable".into())}
        for key in ["request","task","attempt","input_ref","receipt"] {let v=text(row,key)?;if v.is_empty()||v.len()>512||v.chars().any(char::is_control){return Err("chat_history_unavailable".into())}}
        if text(row,"input_ref")?!=format!("{run}:{}",text(row,"request")?){return Err("chat_history_unavailable".into())}
        let auth=field(row,"authority")?;
        if field(auth,"workspace")?!=field(context,"workspace")? || field(auth,"conversation")?!=field(context,"conversation")? {return Err("chat_history_unavailable".into())}
        ordinary_chat::check_text(text(row,"user")?)?;ordinary_chat::check_text(text(row,"answer")?)?;
        let mut ancestors=std::collections::BTreeSet::new();
        let mut previous=None;
        for a in field(row,"ancestors")?.array()? {
            let id=a.string()?;
            if id==run||!seen.contains(id)||!ancestors.insert(id){return Err("chat_history_unavailable".into())}
            let position=rows[..index].iter().position(|u|field(u,"run").ok()==Some(&string(id))).ok_or("chat_history_unavailable")?;
            if previous.is_some_and(|p|p>=position){return Err("chat_history_unavailable".into())}previous=Some(position);
        }
    }
    Ok(rows.to_vec())
}
pub(crate) fn wire_messages(context:&Json,current:&str)->Result<Vec<Json>> {
    let mut out=Vec::new();
    for unit in units(context)? {
        out.push(object([("role",string("user")),("content",field(&unit,"user")?.clone())]));
        out.push(object([("role",string("assistant")),("content",field(&unit,"answer")?.clone())]));
    }
    ordinary_chat::check_text(current)?;
    out.push(object([("role",string("user")),("content",string(current))]));Ok(out)
}
fn run_from(unit:&Json)->Result<AgentDurableRun> {
    Ok(AgentDurableRun{intent:AgentIntentBinding{request_id:text(unit,"request")?.into(),variant:AgentReadVariant::Inquiry,source_build_identity:text(unit,"build")?.into()},identity:AgentRunIdentity{run_id:text(unit,"run")?.into(),admitted_service_epoch:text(unit,"epoch")?.into(),actual_task:Some(AgentTaskIdentity{task_id:text(unit,"task")?.into(),attempt_id:text(unit,"attempt")?.into()})}})
}
fn unit(run:&AgentDurableRun,b:&BusinessRead)->Result<Json> {
    let ctx=b.source_binding.as_ref().ok_or("chat_history_unavailable")?;
    let task=run.identity.actual_task.as_ref().ok_or("chat_history_unavailable")?;
    let answer=b.events.first().and_then(|e|field(e,"payload").ok()).and_then(|p|field(p,"text").ok()).ok_or("chat_history_unavailable")?;
    let receipt=ordinary_chat::receipt(b.dir.as_ref().ok_or("chat_history_unavailable")?,b)?;
    Ok(object([("request",string(&run.intent.request_id)),("run",string(&run.identity.run_id)),("epoch",string(&run.identity.admitted_service_epoch)),("build",string(&run.intent.source_build_identity)),("task",string(&task.task_id)),("attempt",string(&task.attempt_id)),("input_ref",field(ctx,"input_ref")?.clone()),("receipt",string(receipt)),("authority",field(ctx,"authority")?.clone()),("user",field(&b.payload,"text")?.clone()),("answer",answer.clone()),("ancestors",Json::Array(units(ctx)?.iter().map(|u|field(u,"run").cloned()).collect::<Result<Vec<_>>>()?))]))
}
fn verify_source(host:&ServiceHostPorts,run:&AgentDurableRun,b:&BusinessRead)->Result<()> {
    if !ordinary_chat::is_chat(b){return Err("chat_history_unavailable".into())}
    let ctx=b.source_binding.as_ref().ok_or("chat_history_unavailable")?;
    let conversation=text(&b.payload,"conversation")?;let user=text(&b.payload,"text")?;
    let authority=host.owner.chat_authority(conversation,user)?;authority.validate(conversation)?;
    if field(ctx,"authority")?!=&authority.json(){return Err("chat_history_unavailable".into())}
    match ordinary_chat::restore_with_host(b.dir.as_ref().ok_or("chat_history_unavailable")?,run,b,Some(host))? {
        AgentRunSnapshot::Terminal{summary} if summary.terminal==AgentTerminal::Completed=>Ok(()),
        _=>Err("chat_history_unavailable".into())
    }
}
/// Candidates come from ordered root index + current terminal proof, never a surviving map.
pub(crate) fn freeze(root:&crate::service_root::ServiceRoot,b:&BusinessRead)->Result<Vec<Json>> {
    let host=b.host.as_ref().ok_or("chat_owner_unconfigured")?;
    let candidates=b.chat_sources.as_ref().ok_or("chat_history_unavailable")?;
    let mut selected=Vec::new();
    for run in candidates {
        let source=supplier_business::load(&root.run_dir(&run.identity.run_id)?).map_err(|_|"chat_history_unavailable")?;
        if !ordinary_chat::is_chat(&source) {continue}
        if field(&source.payload,"conversation")?!=field(&b.payload,"conversation")? {continue}
        verify_source(host,run,&source)?;
        let current=host.owner.chat_authority(text(&b.payload,"conversation")?,text(&b.payload,"text")?)?;
        if field(source.source_binding.as_ref().ok_or("chat_history_unavailable")?,"workspace")?!=&string(current.workspace){return Err("chat_history_unavailable".into())}
        if selected.len()==MAX_TURNS{return Err("chat_context_limit".into())}
        selected.push(unit(run,&source)?);
    }
    Ok(selected)
}
/// Recheck every frozen ancestor; no recursion, path supplied by the trusted root only.
pub(crate) fn revalidate(parent:&Path,host:&ServiceHostPorts,context:&Json)->Result<()> {
    let selected=units(context)?;
    for (i,frozen) in selected.iter().enumerate() {
        let run=run_from(frozen)?;
        let source=supplier_business::load(&parent.join(&run.identity.run_id)).map_err(|_|"chat_history_unavailable")?;
        verify_source(host,&run,&source)?;
        if unit(&run,&source)?!=*frozen{return Err("chat_history_unavailable".into())}
        let source_context=source.source_binding.as_ref().ok_or("chat_history_unavailable")?;
        for ancestor in units(source_context)? {
            if !selected[..i].iter().any(|earlier|earlier==&ancestor){return Err("chat_history_unavailable".into())}
        }
    }
    Ok(())
}
