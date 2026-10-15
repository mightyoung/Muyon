# Experimental product host seam v1

Base: `3836149416020a0ac58f9e7ca788c20e66688e0e`. This is the default-off,
transitional PersonalAgent integration, not M03 or the final policy/store migration.
ADR-0005 D2/D5/D8 still apply: one gateway, complete calls only, authorization of
the exact normalized request. Redesign v1.3.2 permits staged ownership; its final
Rust authorization ownership is not claimed here.

## Product entry and ownership

`PersonalAgent` and `MuyonHost.open` accept nullable `coreAgentProcess` of type
`CoreAgentProcessConfig({this.enabled = false, required String executablePath,
required String stateRoot})`. Null/disabled preserves the existing path. Enabling
requires absolute executable/state paths controlled by the trusted host, never by
model text or a new UI field. Invalid enabled configuration fails closed.
The configuration is defined/exported by `assistant/core_agent_process.dart`.

The real facade creates its usual task/conversation/scope context, chooses its
backend once, then lets the SAME Rust `Agent` drive its loop. No simultaneous Dart
model.advance/AgentDispatch recursion, no fallback after Rust failure. Existing
start/confirm/cancel/close signatures and legacy startTool behavior remain.
Core-owned tasks reject unsupported resume, pause, compaction or UI continuation
explicitly, including after restart; they must not enter the legacy loop.

Rust exposes explicit `host-session`; legacy CLI/defaults, scripted/SSE providers,
fixture snapshots, fixture-only replay semantics and their checks remain valid.
The existing Agent drive loop gains injected provider/authorization/tool ports;
a separate host agent loop or inquiry.object→fixture.record translation is invalid.
Host invocation does NOT write fixture effects.db or mint a fixture receipt.

The bounded host profile permits at most TWO model turns and ONE read-only
`inquiry.object` invocation. Turn two advertises no tools. A further tool proposal
stops with `unsupported_tool_turn`. Host/Rust-issued invocation identity is distinct
in meaning from model callId; callId only pairs assistant/tool messages and never
becomes a replay/authorization key.

## Host model and tool authority

The host freezes the actual registered inquiry.object descriptor and profile.
Rust provides structured messages; the host constructs the exact `ModelRequest`
with its frozen profile/tools, computes the existing digest, and uses the real
model gate, HostModelAuthorization prepare/take/run, current-scope checks,
beforeSend and gateway ledger. Authorization may not substitute ctx.view(task)
for the projected request. No model capability auto-probe, retry or fallback.
The product path consumes the gateway's typed events; it need not use the lab SSE
codec. Only a complete call + Done(toolCalls), or text + Done(stop), is accepted.

Keep grant creation/approval out of this adapter. Denial stops before invoke or
next model request. If the current model/tool policy requires manual confirmation,
this first limited backend returns explicit `core_confirmation_required` denial;
it does not auto-approve or fall through to legacy. Full confirmation UX is not
claimed; the disabled legacy path retains its existing behavior.

Use the actual ToolRegistry.prepare/invoke/receiptFor and inquiry.object handler
with original task scope. Install ordinary invocation/task ownership before
registry calls. The host-issued opaque prepared_ref maps to the live prepared
object, exact task/attempt/invocation/callId/tool/arguments and current authority.
Invoke consumes that live binding once and rechecks current scope/policy. Echoing
an approved boolean, model ID or arbitrary serialized prepared object is invalid.
Original ToolCallResult/registry receipt stay host-local and remain authoritative.

## Result projection and non-secret boundary

A successful original result/receipt must contain exactly one matching inquiry
ObjectRef for the requested type/id and prepared scope. Construct this projection
field-by-field (not result.toJson or ObjectRef.toJson):

```json
{"found":true,"objectRefs":[{"moduleId":"inquiry","objectType":"supplier","objectId":"synthetic-id","revisionRef":null,"contentDigest":null}]}
```

Use the actual returned revisionRef/contentDigest, including null; never invent a
version/digest. Only those five ref fields are allowed. Required identity strings
are nonempty; optional metadata is null or a bounded non-control ASCII string
using `[A-Za-z0-9._:/-]`, at most128 bytes. Unsupported metadata fails projection;
do not rewrite a reference into a different identity. No record/data/name/summary,
nativeProjectId, arbitrary business string, profile, endpoint, credentialRef,
header, secret, raw stderr or exception text enters IPC/model context/logs.
Missing records follow the real tool failure, not fabricated found=false success.

Expose only a narrow `@visibleForTesting HttpClient Function()? modelClientFactory`
on MuyonHost.open, passed into the existing OpenAiModelGateway clientFactory. Tests
use that real gateway/ledger/auth with an offline HttpClient, fake SecretStore and
synthetic temporary inquiry database. Do not override chat/chatStream to bypass
the real gateway. The shipped default transport remains unchanged.

## Internal process protocol (not a frozen cross-platform API)

Private stdin/stdout, no listening socket or shell. Each frame is4-byte big-endian
length1..65536 then strict UTF-8 JSON. Duplicate/unknown keys, invalid types,
depth>32, unsupported versions and malformed/truncated frames fail closed.
stdout is protocol-only; stderr/errors are fixed sanitized codes. Child starts
with a sanitized environment, not inherited model credentials/proxies/eval flags.

All frames have `v:1,kind`. Start has `task_id,attempt_id,scope_ref,prompt,tool`;
tool is the actual frozen `{name,description,parameters}`, name=inquiry.object.
Task/attempt IDs are host-issued `[A-Za-z0-9_-]{1,96}`; no model-selected path.
Callbacks share `request_id,task_id,attempt_id,turn`; request_id is monotonically
Rust-issued, one outstanding request. Every callback must echo all four exactly.

| Kind/direction | Additional fields |
| --- | --- |
| model_request Rust→host | messages,tools (first turn one descriptor; second []) |
| model_reply host→Rust | reply: exact answer or tool object below |
| prepare Rust→host | invocation_id,call_id,tool,arguments |
| decision host→Rust | invocation_id,decision,prepared_ref |
| invoke Rust→host | invocation_id,call_id,tool,arguments,prepared_ref |
| tool_result host→Rust | invocation_id,prepared_ref,receipt_ref,projection |
| callback_error host→Rust | code (fixed allowlist below) |

reply is exactly `{kind:"answer",text}` or
`{kind:"tool",call_id,name:"inquiry.object",arguments:{type,id}}`.
Model approval/scope/risk/credential fields reject. decision is permit, denied or
confirmation_required; prepared_ref is nonempty only for permit, otherwise null.
Tool result projection is the exact camelCase shape above. receipt_ref is an
opaque host reference to the original registry result, never model-created.
callback_error codes: model_denied,model_confirmation_required,model_failed,
tool_denied,tool_confirmation_required,tool_failed,projection_rejected.

Host cancel/close frames carry task_id,attempt_id and may interrupt a callback.
Terminal Rust→host carries task_id,attempt_id,status,reason,answer,receipt_ref,
projection,model_turns,tool_invocations; nullable fields are always present.
status is completed,denied,cancelled,interrupted,failed,budget_exhausted.
Messages use actual ModelMessage JSON roles/content/tool_calls/tool_call_id; calls
contain original callId/name/JSON arguments; only the accepted projection becomes
tool content. Neither side reconstructs tool evidence from display strings.

Limits:2model turns,1invocation,8history messages,8192-byte prompt/arguments/
projection,16384-byte answer,65536-byte request/frame,262144 aggregate IPC bytes.
Argument type<=32bytes,id<=128bytes; unsupported schemas/values fail explicitly.
Trusted process defaults idle5000ms,total30000ms; test overrides positive values
no greater than these maxima. Cancellation poll<=20ms. Check bounds before growth
or dispatch. Timeout/EOF/wrong correlation cannot count as success or trigger retry.

Before invoke: cancel→cancelled/cancel_requested; close→interrupted/host_closed.
Model/prepare timeout→failed/callback_timeout; EOF→interrupted/host_eof.
After invoke admission, missing result→interrupted/tool_outcome_unknown. Retain any
accepted genuine result on cancellation and start no further model send. Host
registry original receipt remains true even if the child disappears. Wrong or
duplicate callback→failed/callback_mismatch; limit→budget_exhausted/host_budget.

## Required offline evidence

Actual PersonalAgent facade through real compiled Rust, actual registered
inquiry.object and temporary synthetic store; captured second gateway request
must contain the original paired callId and projected actual result. Observe an
original registry receipt and exactly one invocation. A transport test utility
may transparently record the real process I/O, never replace the core in the
positive roundtrip. Errors/permission refusal/cancel/close must assert behavior,
not only missing markers/timeouts.

Cover disabled legacy path, invalid enabled config/no fallback, one loop, complete
turn validation, scope denial/zero invocation, forged model fields, callback ID
mismatch, bounded projection, secret canary absence in IPC/context/logs, cancel
while model pending, close/reap, original result preservation and unsupported
continuation. Use barriers/Completers rather than sleep races. Device tests remain
NOT_RUN. No real model, credential configuration, real data read/write, history
migration or new default permission behavior is authorized.

Keep immutable compiling semantic RED, unchanged independent expectations, actual
GREEN, targeted inverse controls and non-author source review. Missing binary,
compile error or timeout is not semantic RED/KILLED. Raw logs stay outside Git.
Final delivery is a draft PR at exact SHA plus terminal CI; NO merge of that PR.
