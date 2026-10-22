# Independent Android Service Agent — refusing checkpoint

Base: de83e44758ba036b94779cc00d439224b1d06973. This is the test-first compiling host controller seam, not a working Agent runtime. Outer B and trusted persistent in-Service Catalog are approved design; Linux child host remains unchanged. No UI-process Agent implementation is introduced.

The plain host controller uses explicit trusted AgentHostServiceConfig.build_identity and needs no build environment variable. The bridge public AgentServiceConfig remains protocol/private_root only and injects compile-bound MUYON_BRIDGE_BUILD_ID. Existing diagnostic function signatures/parameter spellings and configs are preserved. The host has no UniFFI dependency; one macro DTO inventory expands into distinct plain host/UniFFI types and thin bidirectional conversion, not business logic.

Separate integration target service_controller has four named cases:

- service_controller_executes_registered_read
- controller_is_send_sync_without_moving_native_session
- build_identity_is_explicit_without_host_build_environment
- zero_client_initialization_retirement_requires_real_settlement

Primary marker: AGENT_SERVICE_STUB_REACHED code=internal_failure.
Primary positive assertion: AGENT_SERVICE_RED: admitted run must complete the registered physical read.

The first guard proves constructor/connect/visibility/start/controller refusal only. It does not prove Agent dispatch or physical reads. The post-positive assertions require actual paired task identity, original raw receipt success, exact source/request/variant and read-only lookup, but they are not reached in this initial RED. Later engine GREEN/probe must prove real drive/registered handler/store/two payloads independently, without manufactured public counts.

retire_service and await_settled are Service-only FFI lifecycle methods, never AIDL. The refusing retirement test requires Closing first, then actual settled Closed, then idempotent Closed; this stub intentionally cannot satisfy the settled positive. No worker/store/Agent is instantiated by the refusing checkpoint, no false normal Terminal or Closed is returned. This checkpoint does not implement root validation/liveness policy or transport/authority logic; those require the authorized GREEN phase after independent actual Rust+generated-JVM RED.

Raw logs and source/artifact identities are outside Git. Local host --no-run compiled successfully and the primary test failed semantically (exit101,0passed/1failed/3filtered). Bridge compile, actual generated JVM and Android build/runtime are NOT_RUN at this checkpoint; root/checker remote gates supply those before GREEN. No old native_read25/Core/Plugin sources/tests, permissions, SDK/NDK tools, real models or devices were changed.
