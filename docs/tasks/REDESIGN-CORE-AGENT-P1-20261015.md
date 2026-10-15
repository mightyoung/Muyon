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
