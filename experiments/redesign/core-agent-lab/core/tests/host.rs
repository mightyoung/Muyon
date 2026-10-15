//! Protocol tests use the compiled core and an in-process synthetic host.
//! They do not claim a product registry, model, credential or device execution.
use muyon_core_agent_lab::wire_json::{self, Json, object, string};
use std::{fs, io::{Read, Write}, path::PathBuf, process::{Command, Stdio}, sync::atomic::{AtomicU64, Ordering}, time::Instant};
use std::os::fd::AsRawFd;

static NEXT: AtomicU64 = AtomicU64::new(0);
struct HostProcess {
    child: std::process::Child,
    input: Option<std::process::ChildStdin>,
    output: std::process::ChildStdout,
    root: PathBuf,
    started: Instant,
}
impl HostProcess {
    fn new() -> Self {
        Self::with_deadlines(5000, 30000)
    }
    fn with_deadlines(idle_ms: u64, total_ms: u64) -> Self {
        let root = std::env::temp_dir().join(format!("core-host-test-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
        fs::create_dir(&root).unwrap();
        let started = Instant::now();
        let mut child = Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab"))
            .arg("host-session").arg("--root").arg(&root)
            .arg("--idle-ms").arg(idle_ms.to_string()).arg("--total-ms").arg(total_ms.to_string())
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
        let input = child.stdin.take().unwrap();
        let output = child.stdout.take().unwrap();
        Self { child, input: Some(input), output, root, started }
    }
    fn send(&mut self, value: Json) {
        let bytes = value.encode().into_bytes();
        self.send_raw(&(bytes.len() as u32).to_be_bytes());
        self.send_raw(&bytes);
    }
    fn send_raw(&mut self, bytes: &[u8]) {
        self.input.as_mut().unwrap().write_all(bytes).unwrap();
        self.input.as_mut().unwrap().flush().unwrap();
    }
    fn close_input(&mut self) {
        self.input.take();
    }
    fn receive(&mut self) -> Json {
        let mut header = [0u8; 4];
        self.output.read_exact(&mut header).unwrap();
        let size = u32::from_be_bytes(header) as usize;
        assert!((1..=65536).contains(&size), "host frame must be bounded");
        let mut bytes = vec![0; size];
        self.output.read_exact(&mut bytes).unwrap();
        wire_json::parse(&bytes).unwrap()
    }
}
impl Drop for HostProcess {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_dir_all(&self.root);
    }
}
fn number(value: u64) -> Json { Json::Number(value.to_string()) }
fn descriptor() -> Json {
    object([
        ("name", string("inquiry.object")), ("description", string("Read a scoped synthetic object")),
        ("parameters", object([
            ("type", string("object")),
            ("properties", object([
                ("type", object([("type", string("string")), ("enum", Json::Array(vec![string("supplier")]))])),
                ("id", object([("type", string("string"))])),
            ])),
            ("required", Json::Array(vec![string("type"), string("id")])),
            ("additionalProperties", Json::Bool(false)),
        ])),
    ])
}
fn start() -> Json {
    object([
        ("v", number(1)), ("kind", string("start")),
        ("task_id", string("host-task")), ("attempt_id", string("host-attempt")),
        ("scope_ref", string("scope:synthetic")), ("prompt", string("Find the synthetic supplier")),
        ("tool", descriptor()),
    ])
}
fn args() -> Json { object([("type", string("supplier")), ("id", string("synthetic-id"))]) }
fn projected_result() -> Json {
    object([
        ("found", Json::Bool(true)),
        ("objectRefs", Json::Array(vec![object([
            ("moduleId", string("inquiry")), ("objectType", string("supplier")),
            ("objectId", string("synthetic-id")), ("revisionRef", string("17")),
            ("contentDigest", Json::Null),
        ])])),
    ])
}
fn field<'a>(value: &'a Json, key: &str) -> &'a Json { value.object().unwrap().get(key).unwrap() }
fn text<'a>(value: &'a Json, key: &str) -> &'a str { field(value, key).string().unwrap() }
fn request(process: &mut HostProcess, expected: &str, request_id: u64, turn: u64) -> Json {
    let value = process.receive();
    assert_eq!(text(&value, "kind"), expected, "HOST_ROUNDTRIP_REQUIRES_REAL_AGENT_CALLBACK: elapsed_ms={} {}", process.started.elapsed().as_millis(), value.encode());
    assert_eq!(field(&value, "request_id"), &number(request_id));
    assert_eq!(field(&value, "turn"), &number(turn));
    assert_eq!(text(&value, "task_id"), "host-task");
    assert_eq!(text(&value, "attempt_id"), "host-attempt");
    value
}
fn callback(kind: &str, request_id: u64, turn: u64, extra: Vec<(&str, Json)>) -> Json {
    let mut fields = vec![
        ("v", number(1)), ("kind", string(kind)), ("request_id", number(request_id)),
        ("task_id", string("host-task")), ("attempt_id", string("host-attempt")), ("turn", number(turn)),
    ];
    fields.extend(extra);
    object(fields)
}

#[test]
fn host_roundtrip_pairs_the_original_projected_result_in_turn_two() {
    let mut process = HostProcess::new();
    process.send(start());
    let first = request(&mut process, "model_request", 1, 1);
    assert_eq!(field(&first, "tools"), &Json::Array(vec![descriptor()]));
    process.send(callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("tool")), ("call_id", string("provider-call")),
        ("name", string("inquiry.object")), ("arguments", args()),
    ]))]));
    let prepared = request(&mut process, "prepare", 2, 1);
    let invocation = text(&prepared, "invocation_id").to_string();
    assert_ne!(invocation, "provider-call", "model call ID is pairing-only");
    assert_eq!(text(&prepared, "call_id"), "provider-call");
    assert_eq!(text(&prepared, "tool"), "inquiry.object");
    assert_eq!(field(&prepared, "arguments"), &args());
    process.send(callback("decision", 2, 1, vec![
        ("invocation_id", string(&invocation)), ("decision", string("permit")),
        ("prepared_ref", string("prepared:original")),
    ]));
    let invoked = request(&mut process, "invoke", 3, 1);
    assert_eq!(text(&invoked, "invocation_id"), invocation);
    assert_eq!(text(&invoked, "prepared_ref"), "prepared:original");
    assert_eq!(field(&invoked, "arguments"), &args());
    process.send(callback("tool_result", 3, 1, vec![
        ("invocation_id", string(&invocation)), ("prepared_ref", string("prepared:original")),
        ("receipt_ref", string("receipt:original")), ("projection", projected_result()),
    ]));
    let second = request(&mut process, "model_request", 4, 2);
    assert_eq!(field(&second, "tools"), &Json::Array(vec![]));
    let history = field(&second, "messages").array().unwrap();
    assert_eq!(history.len(), 3);
    let call = &field(&history[1], "tool_calls").array().unwrap()[0];
    assert_eq!(text(&history[1], "role"), "assistant");
    assert_eq!(text(call, "id"), "provider-call");
    assert_eq!(text(field(call, "function"), "name"), "inquiry.object");
    assert_eq!(wire_json::parse(text(field(call, "function"), "arguments").as_bytes()).unwrap(), args());
    assert_eq!(text(&history[2], "role"), "tool");
    assert_eq!(text(&history[2], "tool_call_id"), "provider-call");
    let result = wire_json::parse(text(&history[2], "content").as_bytes()).unwrap();
    assert_eq!(result, projected_result(), "follow-up must contain the actual accepted host projection");
    // Derive the answer from the actual received result, not a DUT placeholder.
    let object_id = text(&field(&result, "objectRefs").array().unwrap()[0], "objectId");
    let answer = format!("Found {object_id}");
    process.send(callback("model_reply", 4, 2, vec![("reply", object([
        ("kind", string("answer")), ("text", string(&answer)),
    ]))]));
    let terminal = process.receive();
    assert_eq!(text(&terminal, "kind"), "terminal");
    assert_eq!(text(&terminal, "status"), "completed");
    assert_eq!(text(&terminal, "answer"), answer);
    assert_eq!(field(&terminal, "projection"), &projected_result());
    assert_eq!(text(&terminal, "receipt_ref"), "receipt:original");
    assert_eq!(field(&terminal, "model_turns"), &number(2));
    assert_eq!(field(&terminal, "tool_invocations"), &number(1));
    assert!(process.child.wait().unwrap().success());
    let attempt_dir = process.root.join("host-task/host-attempt");
    assert!(!attempt_dir.join("effects.db").exists(), "host invokes must not create fixture effects in the actual Agent directory");
    assert!(!attempt_dir.join("task.db").exists(), "host snapshots must remain separate from fixture snapshots");
}

fn propose(process: &mut HostProcess) -> Json {
    process.send(start());
    request(process, "model_request", 1, 1);
    process.send(callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("tool")), ("call_id", string("provider-call")),
        ("name", string("inquiry.object")), ("arguments", args()),
    ]))]));
    request(process, "prepare", 2, 1)
}
fn admit_tool(process: &mut HostProcess) -> String {
    let prepared = propose(process);
    let invocation = text(&prepared, "invocation_id").to_string();
    process.send(callback("decision", 2, 1, vec![
        ("invocation_id", string(&invocation)), ("decision", string("permit")),
        ("prepared_ref", string("prepared:original")),
    ]));
    request(process, "invoke", 3, 1);
    invocation
}
fn result(process: &mut HostProcess, invocation: &str, projection: Json) {
    process.send(callback("tool_result", 3, 1, vec![
        ("invocation_id", string(invocation)), ("prepared_ref", string("prepared:original")),
        ("receipt_ref", string("receipt:original")), ("projection", projection),
    ]));
}
fn terminal(process: &mut HostProcess, status: &str, reason: &str, invocations: u64) -> Json {
    let value = process.receive();
    assert_eq!(text(&value, "kind"), "terminal", "{}", value.encode());
    assert_eq!(text(&value, "status"), status, "{}", value.encode());
    assert_eq!(text(&value, "reason"), reason, "{}", value.encode());
    assert_eq!(field(&value, "tool_invocations"), &number(invocations));
    assert_eq!(field(&value, "answer"), &Json::Null);
    assert!(process.child.wait().unwrap().success());
    value
}
fn control(process: &mut HostProcess, kind: &str) {
    process.send(object([
        ("v", number(1)), ("kind", string(kind)),
        ("task_id", string("host-task")), ("attempt_id", string("host-attempt")),
    ]));
}

#[test]
fn host_denial_stops_before_the_first_invocation() {
    let mut process = HostProcess::new();
    let prepared = propose(&mut process);
    process.send(callback("decision", 2, 1, vec![
        ("invocation_id", field(&prepared, "invocation_id").clone()),
        ("decision", string("denied")), ("prepared_ref", Json::Null),
    ]));
    terminal(&mut process, "denied", "tool_denied", 0);
}

#[test]
fn host_confirmation_requirement_never_becomes_automatic_approval() {
    let mut process = HostProcess::new();
    let prepared = propose(&mut process);
    process.send(callback("decision", 2, 1, vec![
        ("invocation_id", field(&prepared, "invocation_id").clone()),
        ("decision", string("confirmation_required")), ("prepared_ref", Json::Null),
    ]));
    terminal(&mut process, "denied", "core_confirmation_required", 0);
}

#[test]
fn host_wrong_callback_identity_cannot_invoke_or_start_another_turn() {
    let mut process = HostProcess::new();
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    process.send(callback("model_reply", 2, 1, vec![("reply", object([
        ("kind", string("answer")), ("text", string("untrusted")),
    ]))]));
    terminal(&mut process, "failed", "callback_mismatch", 0);
}

#[test]
fn host_forged_approval_in_model_arguments_is_rejected() {
    let mut process = HostProcess::new();
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    process.send(callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("tool")), ("call_id", string("provider-call")),
        ("name", string("inquiry.object")),
        ("arguments", object([("type", string("supplier")), ("id", string("synthetic-id")), ("approved", Json::Bool(true))])),
    ]))]));
    terminal(&mut process, "failed", "host_protocol", 0);
}

#[test]
fn host_cancel_during_model_callback_is_terminal_without_a_tool() {
    let mut process = HostProcess::new();
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    control(&mut process, "cancel");
    terminal(&mut process, "cancelled", "cancel_requested", 0);
}

#[test]
fn host_close_during_model_callback_is_terminal_and_reaped() {
    let mut process = HostProcess::new();
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    control(&mut process, "close");
    terminal(&mut process, "interrupted", "host_closed", 0);
}

#[test]
fn host_silent_callback_has_a_semantic_timeout_terminal() {
    let mut process = HostProcess::with_deadlines(1000, 5000);
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    terminal(&mut process, "failed", "callback_timeout", 0);
}

#[test]
fn host_cancel_after_invoke_keeps_the_original_result_and_stops() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    control(&mut process, "cancel");
    result(&mut process, &invocation, projected_result());
    let value = terminal(&mut process, "cancelled", "cancel_requested", 1);
    assert_eq!(text(&value, "receipt_ref"), "receipt:original");
    assert_eq!(field(&value, "projection"), &projected_result());
}

#[test]
fn host_close_after_invoke_keeps_the_original_result_and_stops() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    control(&mut process, "close");
    result(&mut process, &invocation, projected_result());
    let value = terminal(&mut process, "interrupted", "host_closed", 1);
    assert_eq!(text(&value, "receipt_ref"), "receipt:original");
    assert_eq!(field(&value, "projection"), &projected_result());
}

#[test]
fn host_cancel_after_invoke_without_result_stays_unknown() {
    let mut process = HostProcess::with_deadlines(1000, 5000);
    admit_tool(&mut process);
    control(&mut process, "cancel");
    let value = terminal(&mut process, "interrupted", "tool_outcome_unknown", 1);
    assert_eq!(field(&value, "receipt_ref"), &Json::Null);
    assert_eq!(field(&value, "projection"), &Json::Null);
}

#[test]
fn host_projection_cannot_smuggle_a_raw_record() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    let mut projection = projected_result().object().unwrap().clone();
    projection.insert("record".into(), string("PRIVATE_RECORD_CANARY"));
    result(&mut process, &invocation, Json::Object(projection));
    let value = terminal(&mut process, "failed", "projection_rejected", 1);
    assert!(!value.encode().contains("PRIVATE_RECORD_CANARY"));
    assert_eq!(field(&value, "projection"), &Json::Null);
}

#[test]
fn host_second_tool_proposal_never_dispatches_again() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    result(&mut process, &invocation, projected_result());
    request(&mut process, "model_request", 4, 2);
    process.send(callback("model_reply", 4, 2, vec![("reply", object([
        ("kind", string("tool")), ("call_id", string("another-provider-call")),
        ("name", string("inquiry.object")), ("arguments", args()),
    ]))]));
    let value = terminal(&mut process, "failed", "unsupported_tool_turn", 1);
    assert_eq!(field(&value, "projection"), &projected_result());
}

#[test]
fn host_request_id_requires_an_integer_not_a_json_float() {
    let mut process = HostProcess::new();
    process.send(start());
    request(&mut process, "model_request", 1, 1);
    let mut reply = callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("answer")), ("text", string("invalid correlation")),
    ]))]).object().unwrap().clone();
    reply.insert("request_id".into(), Json::Number("1.0".into()));
    process.send(Json::Object(reply));
    terminal(&mut process, "failed", "host_protocol", 0);
}

#[test]
fn host_matching_oversized_projection_is_rejected_without_unknown_or_result() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    let projection = object([
        ("found", Json::Bool(true)),
        ("objectRefs", Json::Array(vec![object([
            ("moduleId", string("inquiry")), ("objectType", string("supplier")),
            ("objectId", string("synthetic-id")), ("revisionRef", string("x".repeat(8193))),
            ("contentDigest", Json::Null),
        ])])),
    ]);
    result(&mut process, &invocation, projection);
    let value = terminal(&mut process, "failed", "projection_rejected", 1);
    assert_eq!(field(&value, "receipt_ref"), &Json::Null);
    assert_eq!(field(&value, "projection"), &Json::Null);
}

#[test]
fn host_invocation_identity_is_nonce_issued_and_durably_bound_to_its_attempt() {
    let mut first = HostProcess::new();
    let first_request = propose(&mut first);
    let first_id = text(&first_request, "invocation_id");
    assert!(first_id.starts_with("core:"));
    assert_eq!(first_id.len(), 69, "256-bit OS nonce, never PID/turn or model ID");
    assert!(first_id[5..].bytes().all(|b| b.is_ascii_hexdigit()));
    let bytes = fs::read(first.root.join("host-task/host-attempt/host.db")).unwrap();
    let journal = wire_json::parse(&bytes).unwrap();
    let binding = field(&journal, "binding");
    assert_eq!(text(binding, "invocation_id"), first_id);
    assert_eq!(text(binding, "task_id"), "host-task");
    assert_eq!(text(binding, "attempt_id"), "host-attempt");
    assert_eq!(text(binding, "scope_ref"), "scope:synthetic");
    assert_eq!(field(binding, "turn"), &number(1));
    assert_eq!(text(binding, "call_id"), "provider-call");
    assert_eq!(field(binding, "arguments"), &args());
    let mut second = HostProcess::new();
    let second_request = propose(&mut second);
    assert_ne!(text(&second_request, "invocation_id"), first_id, "new attempts cannot collide on a reused PID/turn");
}

#[test]
fn host_clean_eof_is_distinct_from_a_truncated_header() {
    let mut clean = HostProcess::new();
    clean.send(start()); request(&mut clean, "model_request", 1, 1); clean.close_input();
    terminal(&mut clean, "interrupted", "host_eof", 0);
    let mut partial = HostProcess::new();
    partial.send(start()); request(&mut partial, "model_request", 1, 1);
    partial.send_raw(&[0, 0]); partial.close_input();
    terminal(&mut partial, "failed", "host_protocol", 0);
}

#[test]
fn host_truncated_body_is_a_protocol_failure() {
    let mut process = HostProcess::new();
    process.send(start()); request(&mut process, "model_request", 1, 1);
    process.send_raw(&100u32.to_be_bytes()); process.send_raw(b"{"); process.close_input();
    terminal(&mut process, "failed", "host_protocol", 0);
}

#[test]
fn host_frame_size_is_checked_before_body_allocation() {
    for (length, status, reason) in [(0u32, "failed", "host_protocol"), (65537u32, "budget_exhausted", "host_budget")] {
        let mut process = HostProcess::new();
        process.send(start()); request(&mut process, "model_request", 1, 1);
        process.send_raw(&length.to_be_bytes());
        terminal(&mut process, status, reason, 0);
    }
}

#[test]
fn host_duplicate_keys_and_invalid_utf8_never_become_callbacks() {
    for body in [br#"{"v":1,"v":1,"kind":"model_reply"}"#.to_vec(), vec![b'{', 255, b'}']] {
        let mut process = HostProcess::new();
        process.send(start()); request(&mut process, "model_request", 1, 1);
        process.send_raw(&(body.len() as u32).to_be_bytes()); process.send_raw(&body);
        terminal(&mut process, "failed", "host_protocol", 0);
    }
}

#[test]
fn host_each_byte_framing_is_equivalent_for_a_direct_answer() {
    let mut process = HostProcess::new();
    let bytes = start().encode().into_bytes();
    for byte in (bytes.len() as u32).to_be_bytes().into_iter().chain(bytes) { process.send_raw(&[byte]); }
    request(&mut process, "model_request", 1, 1);
    process.send(callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("answer")), ("text", string("synthetic direct answer")),
    ]))]));
    let value = process.receive();
    assert_eq!(text(&value, "status"), "completed");
    assert_eq!(text(&value, "answer"), "synthetic direct answer");
    assert_eq!(field(&value, "model_turns"), &number(1));
    assert_eq!(field(&value, "tool_invocations"), &number(0));
    assert_eq!(field(&value, "receipt_ref"), &Json::Null);
    assert!(process.child.wait().unwrap().success());
}

#[test]
fn host_existing_attempt_is_never_reopened_or_resent() {
    let mut first = HostProcess::new(); first.send(start()); request(&mut first, "model_request", 1, 1);
    control(&mut first, "cancel"); terminal(&mut first, "cancelled", "cancel_requested", 0);
    let mut child = Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab"))
        .arg("host-session").arg("--root").arg(&first.root)
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
    let mut input = child.stdin.take().unwrap(); let body = start().encode();
    input.write_all(&(body.len() as u32).to_be_bytes()).unwrap(); input.write_all(body.as_bytes()).unwrap(); drop(input);
    let output = child.wait_with_output().unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty(), "no provider callback on reused attempt");
    assert_eq!(String::from_utf8(output.stderr).unwrap(), "error=host_attempt_exists\n");
    assert!(!first.root.join("host-task/host-attempt/effects.db").exists());
}

#[test]
fn host_semantically_invalid_complete_ids_stop_as_model_failure_before_prepare() {
    for id in ["x".repeat(129), "synthetic\nid".into(), "synthetic\u{0}id".into()] {
        let mut process = HostProcess::new();
        process.send(start()); request(&mut process, "model_request", 1, 1);
        process.send(callback("model_reply", 1, 1, vec![("reply", object([
            ("kind", string("tool")), ("call_id", string("provider-call")), ("name", string("inquiry.object")),
            ("arguments", object([("type", string("supplier")), ("id", string(id))])),
        ]))]));
        terminal(&mut process, "failed", "model_failed", 0);
    }
}

#[test]
fn host_wrong_argument_scalar_type_is_a_protocol_failure() {
    let mut process = HostProcess::new();
    process.send(start()); request(&mut process, "model_request", 1, 1);
    process.send(callback("model_reply", 1, 1, vec![("reply", object([
        ("kind", string("tool")), ("call_id", string("provider-call")), ("name", string("inquiry.object")),
        ("arguments", object([("type", string("supplier")), ("id", Json::Bool(true))])),
    ]))]));
    terminal(&mut process, "failed", "host_protocol", 0);
}

#[test]
fn host_cancel_and_close_are_consumed_while_output_is_physically_backpressured() {
    unsafe extern "C" { fn fcntl(fd: i32, cmd: i32, ...) -> i32; }
    for (kind, status, reason) in [("cancel", "cancelled", "cancel_requested"), ("close", "interrupted", "host_closed")] {
        let mut process = HostProcess::new();
        assert_eq!(unsafe { fcntl(process.output.as_raw_fd(), 1031, 4096) }, 4096, "Linux F_SETPIPE_SZ is the deterministic physical barrier");
        let mut starting = start().object().unwrap().clone();
        starting.insert("prompt".into(), string("x".repeat(8000)));
        process.send(Json::Object(starting));
        let mut header = [0u8; 4];
        process.output.read_exact(&mut header).unwrap();
        let declared = u32::from_be_bytes(header) as usize;
        assert!(declared > 4096, "the remaining frame cannot fit in the unread pipe");
        // Do not drain stdout. Header observation proves real partial output;
        // control must be consumed while the rest is physically unable to finish.
        control(&mut process, kind);
        assert_eq!(process.child.wait().unwrap().code(), Some(2));
        let mut stderr = String::new(); process.child.stderr.take().unwrap().read_to_string(&mut stderr).unwrap();
        assert_eq!(stderr, "error=host_partial_output\n");
        let journal = wire_json::parse(&fs::read(process.root.join("host-task/host-attempt/host.db")).unwrap()).unwrap();
        assert_eq!(text(&journal, "status"), status, "control was consumed, not replaced by idle timeout");
        assert_eq!(text(&journal, "reason"), reason);
        assert_eq!(field(&journal, "tool_invocations"), &number(0));
        let mut partial = Vec::new(); process.output.read_to_end(&mut partial).unwrap();
        assert!(partial.len() < declared, "no fabricated completion of the abandoned frame");
        assert!(!String::from_utf8_lossy(&partial).contains("\"kind\":\"terminal\""), "no terminal appended inside a partial frame");
    }
}

#[test]
fn host_unmatched_invoke_result_keeps_unknown_instead_of_accepting_a_receipt() {
    let mut process = HostProcess::new();
    let invocation = admit_tool(&mut process);
    process.send(callback("tool_result", 3, 1, vec![
        ("invocation_id", string(invocation)), ("prepared_ref", string("prepared:different")),
        ("receipt_ref", string("receipt:forged")), ("projection", projected_result()),
    ]));
    let value = terminal(&mut process, "interrupted", "tool_outcome_unknown", 1);
    assert_eq!(field(&value, "receipt_ref"), &Json::Null);
    assert_eq!(field(&value, "projection"), &Json::Null);
}

#[test]
fn host_matching_projection_error_callback_is_definite_rejection() {
    let mut process = HostProcess::new();
    admit_tool(&mut process);
    process.send(callback("callback_error", 3, 1, vec![("code", string("projection_rejected"))]));
    let value = terminal(&mut process, "failed", "projection_rejected", 1);
    assert_eq!(field(&value, "receipt_ref"), &Json::Null);
    assert_eq!(field(&value, "projection"), &Json::Null);
}

#[test]
fn host_final_terminal_backpressure_consumes_control_and_preserves_original_result() {
    unsafe extern "C" { fn fcntl(fd: i32, cmd: i32, ...) -> i32; }
    for (kind, status, reason) in [("cancel", "cancelled", "cancel_requested"), ("close", "interrupted", "host_closed")] {
        let mut process = HostProcess::new();
        assert_eq!(unsafe { fcntl(process.output.as_raw_fd(), 1031, 4096) }, 4096);
        let invocation = admit_tool(&mut process);
        result(&mut process, &invocation, projected_result());
        request(&mut process, "model_request", 4, 2);
        process.send(callback("model_reply", 4, 2, vec![("reply", object([
            ("kind", string("answer")), ("text", string("x".repeat(8000))),
        ]))]));
        let mut header = [0u8; 4]; process.output.read_exact(&mut header).unwrap();
        let declared = u32::from_be_bytes(header) as usize;
        assert!(declared > 4096, "final terminal cannot fit in the unread pipe");
        // This barrier observes the actual final-terminal write, after the
        // matching original result and complete second model turn were accepted.
        // No more stdout is drained until the controlled child exits.
        control(&mut process, kind);
        assert_eq!(process.child.wait().unwrap().code(), Some(2));
        let mut stderr = String::new(); process.child.stderr.take().unwrap().read_to_string(&mut stderr).unwrap();
        assert_eq!(stderr, "error=host_partial_output\n");
        let journal = wire_json::parse(&fs::read(process.root.join("host-task/host-attempt/host.db")).unwrap()).unwrap();
        assert_eq!(text(&journal, "status"), status, "final delivery consumed control rather than timing out with stale completed state");
        assert_eq!(text(&journal, "reason"), reason);
        assert_eq!(field(&journal, "answer"), &Json::Null);
        assert_eq!(text(&journal, "receipt_ref"), "receipt:original");
        assert_eq!(field(&journal, "projection"), &projected_result());
        assert_eq!(field(&journal, "model_turns"), &number(2));
        assert_eq!(field(&journal, "tool_invocations"), &number(1));
        let mut partial = Vec::new(); process.output.read_to_end(&mut partial).unwrap();
        assert!(partial.len() < declared, "partial final terminal is abandoned without appending another frame");
    }
}

#[test]
fn host_truncated_second_turn_eof_delivers_protocol_terminal_and_retains_result() {
    unsafe extern "C" { fn fcntl(fd: i32, cmd: i32, ...) -> i32; }
    let mut process = HostProcess::new();
    assert_eq!(unsafe { fcntl(process.output.as_raw_fd(), 1031, 4096) }, 4096);
    let invocation = admit_tool(&mut process);
    result(&mut process, &invocation, projected_result());
    request(&mut process, "model_request", 4, 2);
    process.send_raw(&100u32.to_be_bytes()); process.send_raw(b"{"); process.close_input();
    let value = terminal(&mut process, "failed", "host_protocol", 1);
    assert_eq!(text(&value, "receipt_ref"), "receipt:original");
    assert_eq!(field(&value, "projection"), &projected_result());
    let journal = wire_json::parse(&fs::read(process.root.join("host-task/host-attempt/host.db")).unwrap()).unwrap();
    assert_eq!(text(&journal, "reason"), "host_protocol", "processed truncated EOF cannot be rediscovered as clean EOF during terminal delivery");
}

#[test]
fn host_new_eof_during_final_terminal_backpressure_is_not_ignored() {
    unsafe extern "C" { fn fcntl(fd: i32, cmd: i32, ...) -> i32; }
    let mut process = HostProcess::new();
    assert_eq!(unsafe { fcntl(process.output.as_raw_fd(), 1031, 4096) }, 4096);
    let invocation = admit_tool(&mut process);
    result(&mut process, &invocation, projected_result());
    request(&mut process, "model_request", 4, 2);
    process.send(callback("model_reply", 4, 2, vec![("reply", object([
        ("kind", string("answer")), ("text", string("x".repeat(8000))),
    ]))]));
    let mut header = [0u8; 4]; process.output.read_exact(&mut header).unwrap();
    let declared = u32::from_be_bytes(header) as usize; assert!(declared > 4096);
    // New EOF is observed while final output is blocked; known EOF must later
    // stay latched, without suppressing live input/control polling globally.
    process.close_input();
    assert_eq!(process.child.wait().unwrap().code(), Some(2));
    let mut stderr = String::new(); process.child.stderr.take().unwrap().read_to_string(&mut stderr).unwrap();
    assert_eq!(stderr, "error=host_partial_output\n");
    let journal = wire_json::parse(&fs::read(process.root.join("host-task/host-attempt/host.db")).unwrap()).unwrap();
    assert_eq!(text(&journal, "status"), "interrupted");
    assert_eq!(text(&journal, "reason"), "host_eof");
    assert_eq!(field(&journal, "answer"), &Json::Null);
    assert_eq!(text(&journal, "receipt_ref"), "receipt:original");
    assert_eq!(field(&journal, "projection"), &projected_result());
    let mut partial = Vec::new(); process.output.read_to_end(&mut partial).unwrap();
    assert!(partial.len() < declared, "no new terminal after a partial output frame");
}

#[test]
fn host_complete_bad_frames_keep_the_same_failure_when_input_is_half_closed() {
    fn frame(body: &[u8]) -> Vec<u8> {
        let mut bytes = (body.len() as u32).to_be_bytes().to_vec(); bytes.extend_from_slice(body); bytes
    }
    let cases = [
        ("invalid_utf8", frame(&[b'{', 255, b'}']), "failed", "host_protocol"),
        ("invalid_json", frame(b"{"), "failed", "host_protocol"),
        ("duplicate_key", frame(br#"{"v":1,"v":1,"kind":"model_reply"}"#), "failed", "host_protocol"),
        ("zero_length", 0u32.to_be_bytes().to_vec(), "failed", "host_protocol"),
        ("oversize_header", 65537u32.to_be_bytes().to_vec(), "budget_exhausted", "host_budget"),
    ];
    for (label, bytes, status, reason) in cases {
        for half_close in [false, true] {
            let mut process = HostProcess::new();
            process.send(start()); request(&mut process, "model_request", 1, 1);
            process.send_raw(&bytes);
            if half_close { process.close_input(); }
            let value = terminal(&mut process, status, reason, 0);
            assert_eq!(field(&value, "projection"), &Json::Null);
            let journal = wire_json::parse(&fs::read(process.root.join("host-task/host-attempt/host.db")).unwrap()).unwrap();
            assert_eq!(text(&journal, "status"), status, "{label} half_close={half_close}: delivery EOF cannot replace an established failure");
            assert_eq!(text(&journal, "reason"), reason, "{label} half_close={half_close}: preserve the first failure classification");
        }
    }
}
