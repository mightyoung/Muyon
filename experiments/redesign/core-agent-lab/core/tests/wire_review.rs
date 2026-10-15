//! Independent-review regressions; uses the component checkpoint's public APIs.
use muyon_core_agent_lab::{model::{ModelRequest,NativeMessage},wire_json::parse,wire_provider::encode_request};
#[test]
fn exactly_32_container_levels_accept_and_33_reject(){
    for scalar in ["","0"]{
        let good=format!("{}{}{}","[".repeat(32),scalar,"]".repeat(32));
        let bad=format!("{}{}{}","[".repeat(33),scalar,"]".repeat(33));
        assert!(parse(good.as_bytes()).is_ok(),"32 containers are supported");
        assert!(parse(bad.as_bytes()).is_err(),"33 containers exceed the frozen limit");
    }
    assert!(parse(format!("{}{}","{\"a\":".repeat(32),"{}".to_string()+&"}".repeat(32)).as_bytes()).is_err());
}
fn request()->ModelRequest{ModelRequest{task:"task".into(),attempt:"attempt".into(),turn:3,messages:vec![],tools:vec!["fixture.record".into()]}}
fn pair(value:&str,receipt:&str)->Vec<NativeMessage>{vec![NativeMessage::AssistantCall{call_ref:"c1".into(),name:"fixture.record".into(),value:value.into()},NativeMessage::ToolResult{call_ref:"c1".into(),value:value.into(),receipt:receipt.into()}]}
#[test]
fn tool_result_value_must_match_its_paired_call(){
    let mut history=pair("hi","r1");history[1]=NativeMessage::ToolResult{call_ref:"c1".into(),value:"changed".into(),receipt:"r1".into()};
    assert!(encode_request(&request(),&history).is_err(),"a paired ID cannot conceal changed original value");
}
#[test]
fn repeated_call_id_cannot_change_value_or_original_receipt(){
    let mut good=pair("hi","r1");good.extend(pair("hi","r1"));assert!(encode_request(&request(),&good).is_ok());
    for (value,receipt) in [("changed","r2"),("hi","r2")] {let mut bad=pair("hi","r1");bad.extend(pair(value,receipt));assert!(encode_request(&request(),&bad).is_err(),"same correlation must retain original value and receipt");}
}
