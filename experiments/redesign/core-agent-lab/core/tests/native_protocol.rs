use muyon_core_agent_lab::{model::{ToolDefinition,ModelRequest,ModelEvent},wire_provider::encode_registered_request,wire_sse::Decoder,wire_json::{self,Json,object,string}};
fn tools()->Vec<ToolDefinition>{vec![ToolDefinition{name:"weather.peek".into(),wire_name:"t_42".into(),parameters:wire_json::parse(br#"{"type":"object","properties":{"station_key":{"type":"string"},"include_history":{"type":"boolean"}},"required":["station_key"],"additionalProperties":false}"#).unwrap()}]}
fn request()->ModelRequest{ModelRequest{task:"t1".into(),attempt:"a1".into(),turn:1,messages:vec![],tools:vec!["weather.peek".into()]}}
fn history()->Json{Json::Array(vec![object([("role",string("user")),("content",string("weather?"))])])}
fn stream(name:&str,args:&str,terminal:bool)->Vec<u8>{
 let function=object([("name",string(name)),("arguments",string(args))]);
 let call=object([("index",Json::Number("0".into())),("id",string("c1")),("type",string("function")),("function",function)]);
 let delta=object([("tool_calls",Json::Array(vec![call]))]);
 let choice=object([("index",Json::Number("0".into())),("delta",delta),("finish_reason",string("tool_calls"))]);
 let chunk=object([("choices",Json::Array(vec![choice]))]);
 let tail=if terminal{"data: [DONE]\n\n"}else{""};format!("data: {}\n\n{}",chunk.encode(),tail).into_bytes()
}
#[test]
fn registered_protocol_preserves_arguments_and_schema(){let t=tools();let result=encode_registered_request(&request(),&history(),&t,"offline-native");if result.as_ref().err().map(String::as_str)==Some("native_protocol_unsupported"){eprintln!("NATIVE_PROTOCOL_STUB_REACHED");}let bytes=result.expect("NATIVE_PROTOCOL_RED: registered schema reaches native payload");let json=wire_json::parse(&bytes).unwrap();let encoded=&json.object().unwrap()["tools"].array().unwrap()[0].object().unwrap()["function"];assert_eq!(encoded.object().unwrap()["name"],string("t_42"));assert_eq!(encoded.object().unwrap()["parameters"],t[0].parameters);let mut d=Decoder::with_tools(&t).unwrap();for b in stream("t_42",r#"{"station_key":"s1","include_history":false}"#,true){d.feed(b).unwrap();}assert_eq!(d.finish().unwrap().event,ModelEvent::HostTool{call_ref:"c1".into(),name:"weather.peek".into(),arguments:object([("station_key",string("s1")),("include_history",Json::Bool(false))])});}
#[test]
fn registered_protocol_rejects_unknown_and_incomplete(){let t=tools();let mut d=Decoder::with_tools(&t).unwrap();let mut failed=false;for b in stream("unknown",r#"{"station_key":"s1"}"#,true){if d.feed(b).is_err(){failed=true;break;}}assert!(failed||d.finish().is_err());let mut d=Decoder::with_tools(&t).unwrap();for b in stream("t_42",r#"{"station_key":"s1"}"#,false){d.feed(b).unwrap();}assert_eq!(d.finish().unwrap_err(),"wire_stream_truncated");}
#[test]
fn registered_protocol_rejects_name_collisions(){let mut t=tools();let mut duplicate=t[0].clone();duplicate.name="other.read".into();t.push(duplicate);assert_eq!(encode_registered_request(&request(),&history(),&t,"offline-native").unwrap_err(),"wire_tool_catalog");assert!(Decoder::with_tools(&t).is_err());let mut r=request();r.tools=vec!["absent".into()];assert_eq!(encode_registered_request(&r,&history(),&tools(),"offline-native").unwrap_err(),"wire_tool_catalog");}

#[test]
fn registered_protocol_advertises_current_subset_and_preserves_history(){
 let mut t=tools();t.push(ToolDefinition{name:"hidden.read".into(),wire_name:"t_99".into(),parameters:t[0].parameters.clone()});
 let visible=wire_json::parse(&encode_registered_request(&request(),&history(),&t,"offline-native").unwrap()).unwrap();
 let advertised=visible.object().unwrap()["tools"].array().unwrap();assert_eq!(advertised.len(),1);assert_eq!(advertised[0].object().unwrap()["function"].object().unwrap()["name"],string("t_42"));
 let args=r#"{"station_key":"s1"}"#;
 let call=object([("id",string("c1")),("type",string("function")),("function",object([("name",string("weather.peek")),("arguments",string(args))]))]);
 let mut rows=history().array().unwrap().to_vec();rows.push(object([("role",string("assistant")),("content",Json::Null),("tool_calls",Json::Array(vec![call]))]));
 rows.push(object([("role",string("tool")),("tool_call_id",string("c1")),("content",string("safe-projection"))]));
 let mut r=request();r.turn=2;r.tools.clear();let full=Json::Array(rows.clone());
 let encoded=wire_json::parse(&encode_registered_request(&r,&full,&t,"offline-native").unwrap()).unwrap();
 assert!(encoded.object().unwrap()["tools"].array().unwrap().is_empty());
 let mapped=&encoded.object().unwrap()["messages"].array().unwrap()[1].object().unwrap()["tool_calls"].array().unwrap()[0];assert_eq!(mapped.object().unwrap()["function"].object().unwrap()["name"],string("t_42"));
 let mut broken=rows[2].object().unwrap().clone();broken.insert("tool_call_id".into(),string("wrong"));rows[2]=Json::Object(broken);
 assert_eq!(encode_registered_request(&r,&Json::Array(rows),&t,"offline-native").unwrap_err(),"wire_unpaired_history");
 let mut unknown=t.clone();unknown.remove(0);assert_eq!(encode_registered_request(&r,&full,&unknown,"offline-native").unwrap_err(),"wire_history_call");
}
