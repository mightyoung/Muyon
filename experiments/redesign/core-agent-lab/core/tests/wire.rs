use muyon_core_agent_lab::{model::{ModelEvent,ModelRequest,Message,Role,NativeMessage},wire_sse::{Decoder,DecodedTurn},wire_provider::encode_request};
fn decode(bytes:&[u8])->Result<DecodedTurn,String>{let mut d=Decoder::new();for b in bytes{d.feed(*b)?;}d.finish()}
const TOOL:&str="data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"fixture__record\",\"arguments\":\"{\\\"value\\\":\\\"hi\\\"}\"}}]},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n";
#[test]
fn fragmented_valid_tool_requires_complete_exchange(){
    let turn=decode(TOOL.as_bytes()).expect("valid fragmented tool must decode");
    assert_eq!(turn.event,ModelEvent::Tool{call_ref:"c1".into(),name:"fixture.record".into(),value:"hi".into()});assert_eq!(turn.usage.prompt,None);
}
#[test]
fn fragmented_answer_and_reported_usage(){
    let stream="data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"你好\\uD83D\\uDE00\"},\"finish_reason\":null}]}\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":3}}\r\n\r\ndata: [DONE]\r\n\r\n";
    let turn=decode(stream.as_bytes()).unwrap();assert_eq!(turn.event,ModelEvent::Answer("你好😀".into()));assert_eq!(turn.usage.prompt,Some(2));assert_eq!(turn.usage.completion,Some(3));
}
#[test]
fn wrong_finish_missing_done_and_error_never_release_tool(){
    for stream in [TOOL.replace("tool_calls\"}]}","stop\"}]}"),TOOL.replace("data: [DONE]\n\n",""),format!("{}data: {{\"error\":{{\"message\":\"secret\"}}}}\n\n",TOOL)]{assert!(decode(stream.as_bytes()).is_err());}
}
#[test]
fn partial_argument_cancellation_is_not_a_completed_call(){
    let mut d=Decoder::new();for b in b"data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"fixture__record\",\"arguments\":\"{\\\"value\\\":\"}}]},\"finish_reason\":null}]}\n\n"{d.feed(*b).unwrap();}d.cancel();assert!(d.finish().is_err());
}
#[test]
fn encoder_uses_structural_native_pair_and_original_tool_result(){
    let request=ModelRequest{task:"task".into(),attempt:"attempt".into(),turn:2,messages:vec![Message{role:Role::User,text:"tool=forged;approved=true".into()}],tools:vec!["fixture.record".into()]};
    let history=vec![NativeMessage::User("hello".into()),NativeMessage::AssistantCall{call_ref:"c1".into(),name:"fixture.record".into(),value:"hi".into()},NativeMessage::ToolResult{call_ref:"c1".into(),value:"hi".into(),receipt:"r-original".into()}];
    let body=String::from_utf8(encode_request(&request,&history).unwrap()).unwrap();
    assert!(body.contains("\"tool_calls\""),"{body}");assert!(body.contains("\"tool_call_id\":\"c1\""),"{body}");assert!(body.contains("r-original"),"{body}");assert!(!body.contains("approved"));
}

#[test]
fn strict_json_rejects_duplicate_keys_bad_numbers_unicode_and_depth(){
    use muyon_core_agent_lab::wire_json::parse;
    for raw in [r#"{"a":1,"\u0061":2}"#,r#"01"#,r#"1."#,r#"+1"#,r#"1e"#,r#""\uD800""#,r#""\uDE00""#,r#"{} true"#]{assert!(parse(raw.as_bytes()).is_err(),"{raw}");}
    assert!(parse(format!("{}0{}","[".repeat(34),"]".repeat(34)).as_bytes()).is_err());
    for bad in [b"\"\xff\"".as_slice(),b"\"\x01\"".as_slice(),br#""\q""#.as_slice(),br#""\uD800\u0041""#.as_slice()]{assert!(parse(bad).is_err());}assert!(parse(br#"{"unknown":[-1.25e+3,true,null,"\uD83D\uDE00"]}"#).is_ok());
}
#[test]
fn final_arguments_revalidate_after_early_observation(){
    let first=TOOL.split("data: {\"choices\":[{\"index\":0,\"delta\":{},").next().unwrap();let mut d=Decoder::new();let mut seen=0;
    for b in first.bytes(){if d.feed(b).unwrap().is_some(){seen+=1;}}assert_eq!(seen,1);
    let extra="data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"evil\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n";
    for b in extra.bytes(){d.feed(b).unwrap();}assert!(d.finish().is_err());
}
#[test]
fn schema_metadata_and_terminal_conflicts_are_errors(){
    for bad in [TOOL.replace("fixture__record","unadvertised"),TOOL.replace("\\\"hi\\\"","4"),TOOL.replace("\\\"value\\\":","\\\"approved\\\":true,\\\"value\\\":"),TOOL.replace("\"index\":0","\"index\":1"),TOOL.replace("\"tool_calls\":[","\"function_call\":["),TOOL.replace("tool_calls\"}]}","length\"}]}"),format!("{TOOL}data: [DONE]\n\n"),TOOL.trim_end().to_string()]{assert!(decode(bad.as_bytes()).is_err(),"{bad}");}
    let conflict=TOOL.replace("\"delta\":{},", "\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"other\"}]},");assert!(decode(conflict.as_bytes()).is_err());
}
#[test]
fn multiline_data_comments_and_ignored_framing_are_supported(){
    let raw="event: ignored\n: comment\ndata: {\"choices\":\ndata: [{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n: trailing\n\n";
    assert_eq!(decode(raw.as_bytes()).unwrap().event,ModelEvent::Answer("ok".into()));
}
#[test]
fn native_pair_mismatch_is_not_encoded(){
    let r=ModelRequest{task:"t".into(),attempt:"a".into(),turn:1,messages:vec![],tools:vec!["fixture.record".into()]};
    let h=vec![NativeMessage::AssistantCall{call_ref:"c".into(),name:"fixture.record".into(),value:"v".into()},NativeMessage::ToolResult{call_ref:"other".into(),value:"v".into(),receipt:"r".into()}];assert!(encode_request(&r,&h).is_err());
}
use std::{fs,path::{Path,PathBuf},process::Command,sync::atomic::{AtomicU64,Ordering}};
static NEXT:AtomicU64=AtomicU64::new(0);
const HELPER:&str=r#"import argparse,json,pathlib,sys,os,signal
p=argparse.ArgumentParser();p.add_argument('--fixture-dir');p.add_argument('--turn');p.add_argument('--capture-dir');a=p.parse_args()
f=pathlib.Path(a.fixture_dir);c=pathlib.Path(a.capture_dir);c.mkdir(exist_ok=True)
(c/('pid-'+a.turn)).write_text(str(os.getpid()))
if (f/'no-read').exists():
 while True: signal.pause()
raw=sys.stdin.buffer.read();(c/('request-'+a.turn+'.json')).write_bytes(raw)
if (f/'silent').exists():
 while True: signal.pause()
response=f/('turn-'+a.turn+'.sse')
if response.exists(): data=response.read_bytes()
else:
 r=json.loads(raw);m=r['messages'];tool=m[-1];call=m[-2]['tool_calls'][0]
 assert tool['role']=='tool' and tool['tool_call_id']==call['id']
 result=json.loads(tool['content']);args=json.loads(call['function']['arguments']);assert result['value']==args['value']
 text=result['receipt']+'|'+result['value']
 data=('data: '+json.dumps({'choices':[{'index':0,'delta':{'content':text},'finish_reason':'stop'}]})+'\n\ndata: [DONE]\n\n').encode()
sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
if (f/'exit-fail').exists(): sys.exit(3)
if (f/'eof-hang').exists():
 os.close(1)
 while True: signal.pause()
"#;
fn fixture(stream:&str,extra:&[&str])->PathBuf{
    let root=std::env::temp_dir().join(format!("wire-core-{}-{}",std::process::id(),NEXT.fetch_add(1,Ordering::SeqCst)));fs::create_dir(&root).unwrap();fs::write(root.join("helper.py"),HELPER).unwrap();fs::write(root.join("turn-1.sse"),stream).unwrap();let dir=root.join("task");
    let out=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args(["start","--dir"]).arg(&dir).args(["--provider","chat-sse","--wire-helper"]).arg(root.join("helper.py")).arg("--wire-fixtures").arg(&root).args(extra).output().unwrap();assert!(out.status.success(),"{}",String::from_utf8_lossy(&out.stderr));dir
}
fn command(dir:&Path,verb:&str,extra:&[&str])->String{let out=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args([verb,"--dir"]).arg(dir).args(extra).output().unwrap();assert!(out.status.success(),"{}",String::from_utf8_lossy(&out.stderr));String::from_utf8(out.stdout).unwrap()}
fn field<'a>(text:&'a str,key:&str)->&'a str{text.lines().find_map(|s|s.strip_prefix(&format!("{key}="))).unwrap()}
#[test]
fn stdio_roundtrip_uses_actual_original_result_and_persistent_counters(){
    let dir=fixture(TOOL,&["--wire-chunk-size","1"]);let result=command(&dir,"run",&[]);assert_eq!(field(&result,"status"),"completed");assert_eq!(field(&result,"effects"),"1");assert_eq!(field(&result,"answer_hex"),muyon_core_agent_lab::hex("r-i-1|hi"));assert_eq!(field(&result,"model_calls"),"2");
    let captured=fs::read(dir.join("wire-capture/request-2.json")).unwrap();let text=String::from_utf8(captured).unwrap();assert!(text.contains("r-i-1")&&text.contains("tool_call_id"));
    let sent:u64=field(&result,"wire_sent_bytes").parse().unwrap();let a=fs::metadata(dir.join("wire-capture/request-1.json")).unwrap().len();let b=fs::metadata(dir.join("wire-capture/request-2.json")).unwrap().len();assert_eq!(sent,a+b);assert_eq!(command(&dir,"run",&[]),result);
}
#[test]
fn missing_done_never_reaches_physical_tool(){
    let dir=fixture(&TOOL.replace("data: [DONE]\n\n",""),&[]);let result=command(&dir,"run",&[]);assert_eq!(field(&result,"effects"),"0");assert_eq!(field(&result,"confirmations"),"0");assert_eq!(field(&result,"status"),"failed");assert_eq!(command(&dir,"run",&[]),result);
}
#[test]
fn nonzero_exit_after_complete_turn_never_reaches_physical_tool(){
    let dir=fixture(TOOL,&[]);fs::write(dir.parent().unwrap().join("exit-fail"),"").unwrap();let result=command(&dir,"run",&[]);assert_eq!(field(&result,"effects"),"0");assert_eq!(field(&result,"reason"),"wire_child_exit");
}
#[test]
fn wire_budget_stops_before_request_and_does_not_reset(){
    let dir=fixture(TOOL,&["--max-wire-total","1"]);let result=command(&dir,"run",&[]);assert_eq!(field(&result,"status"),"budget_exhausted");assert_eq!(field(&result,"effects"),"0");assert_eq!(field(&result,"wire_total_bytes"),"0");assert!(!dir.join("wire-capture").exists());assert_eq!(command(&dir,"run",&[]),result);
}
#[test]
fn silent_and_eof_hanging_children_are_killed_and_reaped(){
    for mode in ["silent","eof-hang"]{let dir=fixture(TOOL,&["--wire-idle-ms","100","--wire-total-ms","500"]);fs::write(dir.parent().unwrap().join(mode),"").unwrap();let result=command(&dir,"run",&[]);assert_eq!(field(&result,"effects"),"0");assert!(field(&result,"reason").ends_with("timeout"));let pid=fs::read_to_string(dir.join("wire-capture/pid-1")).unwrap();assert!(!Path::new(&format!("/proc/{pid}")).exists(),"child must be reaped");}
}
#[test]
fn reopened_inflight_is_terminal_and_never_resends(){
    use muyon_core_agent_lab::agent::{State,Agent,Hooks};let dir=fixture(TOOL,&[]);let mut state=State::load(&dir).unwrap();state.wire_counters.inflight=true;state.counters.calls=1;state.counters.steps=1;state.wire_counters.sent=10;state.save(&dir).unwrap();let mut agent=Agent::open(&dir).unwrap();agent.run(&Hooks::default()).unwrap();assert_eq!(agent.state.reason,"wire_interrupted");assert_eq!(agent.state.counters.calls,1);assert_eq!(agent.state.wire_counters.sent,10);assert!(!dir.join("wire-capture").exists());
}
#[test]
fn silent_stream_cancellation_is_observed_before_timeout(){
    use std::{thread,time::{Duration,Instant}};
    let dir=fixture(TOOL,&["--wire-idle-ms","1000","--wire-total-ms","2000"]);fs::write(dir.parent().unwrap().join("silent"),"").unwrap();
    let child=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args(["run","--dir"]).arg(&dir).stdout(std::process::Stdio::piped()).spawn().unwrap();
    let start=Instant::now();while !dir.join("wire-capture/request-1.json").exists(){assert!(start.elapsed()<Duration::from_secs(5));thread::sleep(Duration::from_millis(2));}
    command(&dir,"cancel",&[]);let output=child.wait_with_output().unwrap();assert!(output.status.success());let text=String::from_utf8(output.stdout).unwrap();assert_eq!(field(&text,"reason"),"wire_cancelled");assert_eq!(field(&text,"effects"),"0");let pid=fs::read_to_string(dir.join("wire-capture/pid-1")).unwrap();assert!(!Path::new(&format!("/proc/{pid}")).exists());
}
#[test]
fn nonreading_child_is_bounded_by_total_deadline(){
    let input="x".repeat(50000);let dir=fixture(TOOL,&["--input",&input,"--wire-idle-ms","2000","--wire-total-ms","300"]);fs::write(dir.parent().unwrap().join("no-read"),"").unwrap();let start=std::time::Instant::now();let result=command(&dir,"run",&[]);let elapsed=start.elapsed();let sent:u64=field(&result,"wire_sent_bytes").parse().unwrap();
    // A 50KB request may fit the OS pipe; this process test claims no blocked-write phase.
    use std::io::Write;std::io::stdout().write_all(format!("nonreading diagnostic: sent={sent} reason={} elapsed_ms={}\n",field(&result,"reason"),elapsed.as_millis()).as_bytes()).unwrap();
    assert_eq!(field(&result,"effects"),"0","{result}");assert_eq!(field(&result,"reason"),"wire_total_timeout","{result}");assert!(sent>0&&sent<=65536,"sent={sent}; {result}");assert!(elapsed<std::time::Duration::from_secs(5));let pid=fs::read_to_string(dir.join("wire-capture/pid-1")).unwrap();assert!(!Path::new(&format!("/proc/{pid}")).exists());
}
#[test]
fn unsupported_multiple_choices_calls_and_wrong_types_reject_whole_turn(){
    let one=r#"{"index":0,"delta":{},"finish_reason":"stop"}"#;
    let choices=format!("data: {{\"choices\":[{one},{one}]}}\n\ndata: [DONE]\n\n");assert!(decode(choices.as_bytes()).is_err());
    let call=r#"{"index":0,"id":"c1","function":{"name":"fixture__record","arguments":"{\"value\":\"hi\"}"}}"#;
    let calls=format!("data: {{\"choices\":[{{\"index\":0,\"delta\":{{\"tool_calls\":[{call},{call}]}},\"finish_reason\":\"tool_calls\"}}]}}\n\ndata: [DONE]\n\n");assert!(decode(calls.as_bytes()).is_err());
    for change in [TOOL.replace("\"index\":0","\"index\":\"0\""),TOOL.replace("\"id\":\"c1\"","\"id\":true"),TOOL.replace("\"delta\":{},","\"delta\":{\"content\":5},"),TOOL.replace("\"delta\":{},","\"delta\":{\"content\":\"mixed\"},")]{assert!(decode(change.as_bytes()).is_err());}
}
#[test]
fn malformed_duplicate_and_nonobject_arguments_are_rejected(){
    for args in [r#"{"value":"hi","value":"evil"}"#,r#"["hi"]"#,r#"{"value":"hi","scope":"privileged"}"#,r#"{"value":"hi"} trailing"#]{let escaped=muyon_core_agent_lab::wire_json::quote(args);let stream=format!("data: {{\"choices\":[{{\"index\":0,\"delta\":{{\"tool_calls\":[{{\"index\":0,\"id\":\"c1\",\"function\":{{\"name\":\"fixture__record\",\"arguments\":{escaped}}}}}]}},\"finish_reason\":\"tool_calls\"}}]}}\n\ndata: [DONE]\n\n");assert!(decode(stream.as_bytes()).is_err(),"{args}");}
}
#[test]
fn metadata_repeats_and_null_fragments_are_supported_but_limits_hold(){
    let identical=TOOL.replace("\"delta\":{},", "\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"fixture__record\",\"arguments\":null}}]},");assert!(decode(identical.as_bytes()).is_ok());
    let oversized=format!(":{}\n\n{}","x".repeat(16385),TOOL);assert!(decode(oversized.as_bytes()).is_err());
    let mut invalid=TOOL.as_bytes().to_vec();invalid[0]=255;assert!(decode(&invalid).is_err());
}
fn tool_stream(args:&str)->String{format!("data: {{\"choices\":[{{\"index\":0,\"delta\":{{\"tool_calls\":[{{\"index\":0,\"id\":\"c1\",\"function\":{{\"name\":\"fixture__record\",\"arguments\":{}}}}}]}},\"finish_reason\":\"tool_calls\"}}]}}\n\ndata: [DONE]\n\n",muyon_core_agent_lab::wire_json::quote(args))}
const ANSWER:&str="data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n";
#[test]
fn exact_json_request_response_line_event_and_argument_byte_boundaries(){
    use muyon_core_agent_lab::wire_json::parse;
    for n in [65536,65537]{let raw=format!("\"{}\"","x".repeat(n-2));assert_eq!(parse(raw.as_bytes()).is_ok(),n==65536);}
    let req=ModelRequest{task:"t".into(),attempt:"a".into(),turn:1,messages:vec![],tools:vec!["fixture.record".into()]};let base=encode_request(&req,&[NativeMessage::User(String::new())]).unwrap().len();
    for n in [65536,65537]{assert_eq!(encode_request(&req,&[NativeMessage::User("x".repeat(n-base))]).is_ok(),n==65536);}
    for n in [65536,65537]{let mut s=ANSWER.to_string();let extra=n-s.len();let lines=extra/100;for _ in 0..lines{s.push_str(&format!(":{}\n","x".repeat(98)));}let rem=n-s.len();if rem>0{s.push(':');s.push_str(&"x".repeat(rem-2));s.push('\n');}assert_eq!(s.len(),n);assert_eq!(decode(s.as_bytes()).is_ok(),n==65536);}
    for n in [16384,16385]{let s=format!(":{}\n{ANSWER}","x".repeat(n-1));assert_eq!(decode(s.as_bytes()).is_ok(),n==16384);}
    let json=r#"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#;
    for n in [16384,16385]{let s=format!("data: {json}\ndata: {}\n\ndata: [DONE]\n\n"," ".repeat(n-json.len()-1));assert_eq!(decode(s.as_bytes()).is_ok(),n==16384);}
    for n in [8192,8193]{let args=format!("{{\"value\":\"{}\"}}","x".repeat(n-12));assert_eq!(args.len(),n);assert_eq!(decode(tool_stream(&args).as_bytes()).is_ok(),n==8192);}
}
#[test]
fn arguments_really_fragment_across_events_and_bad_usage_rejects(){
    let a=r#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"fixture__record","arguments":"{\"value\":"}}]},"finish_reason":null}]}"#;
    let b=r#"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"hi\"}"}}]},"finish_reason":"tool_calls"}]}"#;
    let stream=format!("data: {a}\n\ndata: {b}\n\ndata: [DONE]\n\n");assert_eq!(decode(stream.as_bytes()).unwrap().event,ModelEvent::Tool{call_ref:"c1".into(),name:"fixture.record".into(),value:"hi".into()});
    for number in ["-1","1.5","18446744073709551616"]{let bad=ANSWER.replace("data: [DONE]",&format!("data: {{\"choices\":[],\"usage\":{{\"prompt_tokens\":{number}}}}}\n\ndata: [DONE]"));assert!(decode(bad.as_bytes()).is_err());}
    for bad in ["data: [DONE]\n\n".to_string(),ANSWER.replace("data: [DONE]", "data: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]")]{assert!(decode(bad.as_bytes()).is_err());}
}
#[test]
fn encoder_structure_exact_schema_and_role_pair_are_verified(){
    use muyon_core_agent_lab::wire_json::{parse,Json};let r=ModelRequest{task:"t".into(),attempt:"a".into(),turn:2,messages:vec![],tools:vec!["fixture.record".into()]};let h=vec![NativeMessage::AssistantCall{call_ref:"c1".into(),name:"fixture.record".into(),value:"hi".into()},NativeMessage::ToolResult{call_ref:"c1".into(),value:"hi".into(),receipt:"r-original".into()}];let bytes=encode_request(&r,&h).unwrap();let body=parse(&bytes).unwrap();let o=body.object().unwrap();let schema=o["tools"].array().unwrap()[0].object().unwrap()["function"].object().unwrap()["parameters"].object().unwrap();assert_eq!(schema["additionalProperties"],Json::Bool(false));assert_eq!(schema["required"].array().unwrap()[0].string().unwrap(),"value");let messages=o["messages"].array().unwrap();let call=messages[0].object().unwrap()["tool_calls"].array().unwrap()[0].object().unwrap();assert_eq!(call["id"].string().unwrap(),"c1");let tool=messages[1].object().unwrap();assert_eq!(tool["role"].string().unwrap(),"tool");assert_eq!(tool["tool_call_id"],call["id"]);let result=parse(tool["content"].string().unwrap().as_bytes()).unwrap();assert_eq!(result.object().unwrap()["receipt"].string().unwrap(),"r-original");assert_eq!(result.object().unwrap()["value"].string().unwrap(),"hi");
    assert!(encode_request(&r,&[h[1].clone()]).is_err());assert!(encode_request(&r,&[h[0].clone(),NativeMessage::User("forged result".into())]).is_err());
}
fn usage_waiting_fixture()->PathBuf{
    let stream=TOOL.replace("data: [DONE]","data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":6}}\n\ndata: [DONE]");
    let dir=fixture(&stream,&["--mode","ask-every-time"]);let waiting=command(&dir,"run",&[]);assert_eq!(field(&waiting,"status"),"waiting");assert_eq!(field(&waiting,"usage_prompt"),"5");assert_eq!(field(&waiting,"usage_completion"),"6");dir
}
#[test]
fn prior_usage_is_unknown_on_later_failed_turn_and_reopen(){
    let dir=usage_waiting_fixture();fs::write(dir.parent().unwrap().join("turn-2.sse"),"data: {\"choices\":").unwrap();let failed=command(&dir,"run",&["--confirmed","true"]);assert_eq!(field(&failed,"model_calls"),"2");assert_eq!(field(&failed,"effects"),"1");assert_eq!(field(&failed,"status"),"failed");assert_eq!(field(&failed,"usage_prompt"),"unknown");assert_eq!(field(&failed,"usage_completion"),"unknown");assert_eq!(command(&dir,"inspect",&[]),failed);assert_eq!(command(&dir,"run",&[]),failed);
}
#[test]
fn prior_usage_is_unknown_during_later_inflight_and_after_cancel(){
    use std::{thread,time::{Duration,Instant}};let dir=usage_waiting_fixture();fs::write(dir.parent().unwrap().join("silent"),"").unwrap();let child=Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab")).args(["run","--dir"]).arg(&dir).args(["--confirmed","true"]).stdout(std::process::Stdio::piped()).spawn().unwrap();let start=Instant::now();while !dir.join("wire-capture/request-2.json").exists(){assert!(start.elapsed()<Duration::from_secs(5));thread::sleep(Duration::from_millis(2));}
    let state=muyon_core_agent_lab::agent::State::load(&dir).unwrap();
    command(&dir,"cancel",&[]);let output=child.wait_with_output().unwrap();assert!(output.status.success());assert!(state.wire_counters.inflight);assert_eq!(state.wire_counters.usage.prompt,None);assert_eq!(state.wire_counters.usage.completion,None);let cancelled=String::from_utf8(output.stdout).unwrap();assert_eq!(field(&cancelled,"status"),"cancelled");assert_eq!(field(&cancelled,"usage_prompt"),"unknown");assert_eq!(field(&cancelled,"usage_completion"),"unknown");assert_eq!(field(&cancelled,"effects"),"1");assert_eq!(command(&dir,"inspect",&[]),cancelled);
}
#[test]
fn escaped_private_history_remains_loadable_without_relaxing_wire_limit(){
    let input="\u{1}".repeat(50000);let dir=fixture(TOOL,&["--input",&input]);let initial=command(&dir,"inspect",&[]);assert_eq!(field(&initial,"status"),"ready");assert_eq!(field(&initial,"model_calls"),"0");let failed=command(&dir,"run",&[]);assert_eq!(field(&failed,"reason"),"wire_request_limit");assert_eq!(field(&failed,"effects"),"0");assert_eq!(field(&failed,"wire_total_bytes"),"0");assert_eq!(field(&failed,"model_calls"),"1");assert!(!dir.join("wire-capture").exists());assert_eq!(command(&dir,"inspect",&[]),failed);assert_eq!(command(&dir,"run",&[]),failed);
}
