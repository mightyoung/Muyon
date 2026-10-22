> Latest held schema2/edited preparation slice: [SCHEMA2-REPORT.md](SCHEMA2-REPORT.md).
> Previous results below remain historical; no engine publication is enabled.

# Engine protocol consumption — no engine admission

Read fixed upstream77a000bcb59dd5de3e40887f03fb612622c09e9e HOST-PROTOCOL.md and
protocol.py/runtime.py. No copied third-party engine/worker implementation or launcher.
Rust `engine_protocol` builds schema1 data from real DocumentMetadata plus a typed
numeric-cell request. Gateway wrapper resolves that source/grant freshly in the
BusinessStore transaction. scope_id hashes the full workspace/project Scope;
file/base come from DocumentRef; source_sha256 from the actual managed BlobRef.
Operation/idempotency identity and patch digest bind the full canonical operation,
source/scope/file/revision and original intent. There is no host-path/URL/shell,
caller-selected binary, grant or fake flag in a request.

Numeric decimal spelling is preserved in the request. Normalization is used only
to reject no-op operations; it does not claim5.0 output is identical to5. Formula,
visibility, hidden rows/columns and OOXML semantics are NOT inspected here. The
adapter's hidden-target limitation remains open; all real execution stays HOLD.

PreparedEngineRequest is not deserializable or a capability token. It has a host
clock deadline30seconds. check_response_held returns Result<Infallible,...>: it has
no success value and cannot mint Validation, Candidate, CopyReceipt or commit
permission. Unknown/duplicate keys, wrong schema, identity/hash mismatch,
missing source hash on purported candidate_validated, fake flag, simulation status/
diagnostics and expired host preparations hard-fail. Opaque manifests/oracle data
are explicitly rejected wholesale until a typed consumer is reviewed; nested
unknown paths are not silently ignored. Other well-formed diagnostics remain HOLD.

The durable gateway's only executable action is ByteIdenticalCopy. Engine-prepared
bindings cannot match its stored copy plan. Arbitrary engine responses, including
simulated_validated, have no ingestion path to the durable Validated/Committed
state. apply_engine_patch remains UnsupportedOperation. A same-length different-
hash candidate is refused even if its stored candidate digest is also altered.

Tests use six synthetic response variants and synthetic metadata ONLY, no engine
process/workbook round-trip. They cover live grant source mapping, reviewed copy
intent separation, numeric/cell bounds, wrong keys/version/hash/identity, simulation
hard rejection, expiry without sleep, and preservation of exact numeric literals.
This is protocol validation, not43 upstream fake tests re-counted as real execution.

## Later upstream protocol reviewed, not enabled

Also read fixed6b796c8d6e094d45ef25e28698048c21ef0ae7b3
text-subsets/PROTOCOL-v2.md. This slice remains schema1/XLSX mapping only;
schema2, DOCX and PPTX requests explicitly reject. There is no downgrade or
expanded-tree-json-v1 fingerprint implementation. Its ensure_ascii/attribute order/
null/comment/PI/Unicode golden cases are required before any future v2 consumer.
The updated v1 hidden/protected/merged restrictions require fresh adapter eligibility
and invalidate old previews; this gateway does not claim those inspections or reuse
an old executable preview. Every engine path stays HOLD, including plain well-formed
responses. This delivery completes only the independent COPY slice.
