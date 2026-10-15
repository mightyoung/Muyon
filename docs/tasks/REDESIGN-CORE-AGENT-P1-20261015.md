# P1 — offline byte protocol implementation

Owner rd_core_agent_writer; base75981959070a4b8d6a6158dbb132e48eea8858fa;
SPEC/C0 WIRE-CONTRACT9b569f9ade3c7824bde23d969998f6f16c4655fb.
Only core/ and this document are owned. No product/old checker/fixture changes.

Initial immutable checkpoint preserves five Rust tests against a compiling stub:
valid fragmented tool/answer and structural native encoding fail semantically;
wrong/missing terminals, partial-argument cancellation and trailing error reject.
Local rustc/cargo absent: new compilation/RED NOT_RUN until root's exact CI.
Existing21 C1 tests and8 mutations preserved. No external crates or installations.

Initial typed seams: Decoder::feed(u8)->Result<Option<ArgumentObservation>>;
Decoder::finish()->Result<DecodedTurn>; encode_request(&ModelRequest,
&[NativeMessage])->Result<Vec<u8>>. ArgumentObservation is observation-only;
ModelEvent is released only after protocol and transport completion. Final Agent
injection/control signatures and wire observation counters documented before
integration; public CLI/stdio ABI remains WIRE-CONTRACT.

## Implementation interface checkpoint

- `Provider::respond(&mut self, &ModelRequest, usize) -> Result<ModelEvent>` remains for C1; default `respond_controlled(&mut self, &ModelRequest, usize, &[NativeMessage], &mut dyn ProviderControl) -> Result<ModelEvent>` makes control injectable. `reported_usage(&self) -> (Option<u64>, Option<u64>)` preserves unknown usage.
- `Agent::run_with_provider(&mut self, &mut dyn Provider, &Hooks) -> Result<()>`; CLI `run` selects the frozen configured implementation. `ProviderControl` exposes `poll`, `remaining`, `charge(sent, bytes)`, `checkpoint(name)`. No provider grants host scope/confirmation.
- `Decoder::feed(u8) -> Result<Option<ArgumentObservation>>` produces observation only; `finish(self) -> Result<DecodedTurn>` validates final args and terminal framing. WireProvider calls finish only after clean pipe EOF and child exit0. Structured `NativeMessage` is persisted independently from semantic C1 context.
- Public observation/snapshot keys: `wire_sent_bytes`, `wire_received_bytes`, `wire_total_bytes`, `provider_inflight`, `usage_prompt`, `usage_completion` (unknown or decimal). Existing physical `calls/steps/confirmations` remain. Counts are exact for handled exchanges; SIGKILL syscall-to-snapshot window yields a durable measured lower bound with a permanent no-resend barrier, per parent ruling. No token/price/billing claim.
- Linux std-only nonblocking pipes; bounded request/read chunks and deadline cover stdin, stdout, and EOF-to-exit. Errors/cancel/limits kill and reap. External parent SIGKILL helper cleanup belongs to harness; no parent-death supervision claim.

## Preserved verification history

- `ee6ffb27286463eb281fa59ad92d4b580446ce78`: actual CI38673388381 compiled, original21 Rust passed, newwire5 had 2pass/3 semantic failures; genuine RED.
- `8cb313e40dd4e7454c74e060288a884a05273146`: component CI38673817131 failed compilation (nested request-constructor delimiters); not semantic RED/GREEN. Focused fix `b5c389d21896e318fb87ec1ba49f6e3418e777bb` preserves that result.
- Current stdio/core candidate is not yet runtime-verified. Local Rust remains NOT_RUN. Independent checker, inverse mutations and scoped non-author review remain required before completion.
