# Product Rust Agent host seam — Dart checkpoint

Status: **API/stub checkpoint; runtime validation NOT_RUN locally**.

The existing `PersonalAgent` and `MuyonHost.open` now accept nullable
`coreAgentProcess`. `CoreAgentProcessConfig` defaults to disabled and requires
explicit executable/state paths. Enabled relative paths fail with the fixed
`core_config_invalid` error. Disabled paths are unused.

A valid enabled request enters the real facade's existing task factory,
persists its normal task and user message, then terminates that task as failed
with `core_backend_unavailable`. It does not invoke the legacy model loop. This
deliberately incomplete behavior is the immutable semantic RED checkpoint for
the independently owned host integration tests.

`MuyonHost.open(modelClientFactory: ...)` passes its optional testing transport
factory directly into the existing shared `OpenAiModelGateway`. The gateway's
authorization, outbound ledger and production default transport remain in place.
No model/profile/credential configuration enters the process API.

Local `dart`, `flutter` and `cargo` executables are absent. No runtime or analyzer
pass is claimed; root will run the existing GitHub runner against this compiling
API candidate and preserve its first semantic test failure before full behavior
implementation. No tests, business handlers, registry, grant policy, old runtime
defaults, or Rust sources changed at this checkpoint.
