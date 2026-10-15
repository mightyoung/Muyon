//! Protocol tests use the compiled core and an in-process synthetic host.
//! They do not claim a product registry, model, credential or device execution.
use muyon_core_agent_lab::wire_json::{self, Json, object, string};
use std::{fs, io::{Read, Write}, path::PathBuf, process::{Command, Stdio}, sync::atomic::{AtomicU64, Ordering}};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct HostProcess {
    child: std::process::Child,
    input: std::process::ChildStdin,
    output: std::process::ChildStdout,
    root: PathBuf,
}
impl HostProcess {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!("core-host-test-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
        fs::create_dir(&root).unwrap();
        let mut child = Command::new(env!("CARGO_BIN_EXE_muyon-core-agent-lab"))
            .arg("host-session").arg("--root").arg(&root)
            .args(["--idle-ms", "1000", "--total-ms", "5000"])
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
        let input = child.stdin.take().unwrap();
        let output = child.stdout.take().unwrap();
        Self { child, input, output, root }
    }
    fn send(&mut self, value: Json) {
        let bytes = value.encode().into_bytes();
        self.input.write_all(&(bytes.len() as u32).to_be_bytes()).unwrap();
        self.input.write_all(&bytes).unwrap();
        self.input.flush().unwrap();
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
    assert_eq!(text(&value, "kind"), expected, "HOST_ROUNDTRIP_REQUIRES_REAL_AGENT_CALLBACK: {}", value.encode());
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
    assert!(!process.root.join("effects.db").exists(), "host invokes must not create fixture effects");
}
