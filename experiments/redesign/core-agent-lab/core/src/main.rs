use muyon_core_agent_lab::{Result, agent::{Agent,State,Limits,Hooks,parse_mode,boolean},policy::HostFacts,store};
use std::{collections::BTreeMap,path::PathBuf};
fn take(m:&mut BTreeMap<String,String>,key:&str,default:&str)->String{m.remove(key).unwrap_or_else(||default.into())}
fn flag(m:&mut BTreeMap<String,String>,key:&str,default:bool)->Result<bool>{boolean(&take(m,key,if default{"true"}else{"false"}))}
fn number(m:&mut BTreeMap<String,String>,key:&str,default:u64)->Result<u64>{take(m,key,&default.to_string()).parse().map_err(|_|format!("invalid_{key}"))}
fn require_empty(m:&BTreeMap<String,String>)->Result<()>{if m.is_empty(){Ok(())}else{Err("unknown_option".into())}}
fn execute()->Result<()> {
    let mut args=std::env::args().skip(1);let command=args.next().ok_or("missing_command")?;
    let mut opts=BTreeMap::new();
    while let Some(key)=args.next(){if !key.starts_with("--"){return Err("invalid_option".into());}let value=args.next().ok_or("missing_value")?;if value.len()>65536||opts.insert(key,value).is_some(){return Err("invalid_duplicate_option".into());}}
    let dir=PathBuf::from(opts.remove("--dir").ok_or("missing_dir")?);
    if command=="start" {
        let script=store::read(&PathBuf::from(opts.remove("--script").ok_or("missing_script")?))?;
        let input=take(&mut opts,"--input","");let scope=take(&mut opts,"--scope","fixture");
        let mode=parse_mode(&take(&mut opts,"--mode","auto"))?;
        let high=match take(&mut opts,"--risk","low").as_str(){"low"=>false,"high"=>true,_=>return Err("invalid_risk".into())};
        let facts=HostFacts{mode,high,hard_ok:flag(&mut opts,"--hard-ok",true)?,revoked:flag(&mut opts,"--revoked",false)?,scope_ok:flag(&mut opts,"--scope-ok",true)?,classification_ok:flag(&mut opts,"--classification-ok",true)?,confirmed:flag(&mut opts,"--confirmed",false)?,tainted:flag(&mut opts,"--tainted",false)?,new_destination:flag(&mut opts,"--new-destination",false)?};
        let limits=Limits{steps:number(&mut opts,"--max-steps",16)?,calls:number(&mut opts,"--max-calls",16)?,context:number(&mut opts,"--max-context",65536)?,output:number(&mut opts,"--max-output",16384)?,total:number(&mut opts,"--max-total",262144)?};
        let behavior=take(&mut opts,"--tool-behavior","normal");require_empty(&opts)?;
        let state=State::new(script,input,scope,facts,limits,behavior)?;let agent=Agent::start(&dir,state)?;print!("{}",agent.observe());return Ok(());
    }
    if !matches!(command.as_str(),"run"|"cancel"|"lookup"|"inspect"){return Err("unknown_command".into());}
    store::validate_dir(&dir)?;
    if command=="cancel" {
        require_empty(&opts)?;
        // Independent host signal is atomic and durable even when executor owns flock.
        store::atomic(&dir,"cancel.request","CORE_CANCEL_V1\n")?;
        match store::lock(&dir){
            Ok(_guard)=>{let mut agent=Agent::open(&dir)?;agent.cancel()?;print!("{}",agent.observe());},
            Err(e) if e=="directory_locked"=>{let mut agent=Agent::open(&dir)?;agent.state.cancelled=true;print!("{}",agent.observe());},
            Err(e)=>return Err(e),
        }
        return Ok(());
    }
    let _guard=store::lock(&dir)?;let mut agent=Agent::open(&dir)?;
    match command.as_str(){
        "run"=>{
            if let Some(v)=opts.remove("--confirmed"){
                let confirmed=boolean(&v)?;
                if confirmed && (agent.state.status!="waiting" || agent.state.binding.is_none() || agent.state.unresolved || agent.state.evidence_hold){return Err("confirmation_requires_pending_invocation".into());}
                agent.state.facts.confirmed=confirmed;
            }
            if let Some(v)=opts.remove("--hard-ok"){agent.state.facts.hard_ok=boolean(&v)?;}
            if let Some(v)=opts.remove("--revoked"){agent.state.facts.revoked=boolean(&v)?;}
            if let Some(v)=opts.remove("--scope-ok"){agent.state.facts.scope_ok=boolean(&v)?;}
            if let Some(v)=opts.remove("--classification-ok"){agent.state.facts.classification_ok=boolean(&v)?;}
            let hooks=Hooks{checkpoint:opts.remove("--checkpoint"),io_fault:opts.remove("--io-fault")};
            for point in [&hooks.checkpoint,&hooks.io_fault].into_iter().flatten(){if !matches!(point.as_str(),"dispatch"|"effect"|"projection"){return Err("invalid_checkpoint".into());}}
            require_empty(&opts)?;agent.state.save(&dir)?;agent.run(&hooks)?;
        },
        "lookup"=>{require_empty(&opts)?;agent.lookup()?;},
        "inspect"=>require_empty(&opts)?,
        _=>unreachable!(),
    }
    print!("{}",agent.observe());Ok(())
}
fn main(){if let Err(e)=execute(){eprintln!("error={e}");std::process::exit(2);}}
