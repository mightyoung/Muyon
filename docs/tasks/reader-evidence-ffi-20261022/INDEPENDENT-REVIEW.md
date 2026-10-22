# Independent static review — reader/evidence FFI

Reviewer: separate read-only agent /root/independent_provider_review,2026-10-22.
Reviewed current owned FFI files and exact imported core API; no changes by reviewer.

Original findings preserved:
1. Medium: native full-capacity check preceded core expiry sweep. Eight abandoned
   expired bridge IDs could indefinitely deny admission despite released core pins.
2. Low: query/quote/answer tested processing lifetime only before slow work; their
   output could cross the absolute/idle limit then refresh touched and publish.

Repairs reviewed: bounded at-most8 genuine core checks at full admission; encoded
owned evidence passes corrected public exact-metadata delivery gate, then lifetime
check before touch/reinsert. No redundant full-file check in chunk. Gate callback
has no nested transaction or delivery, no lifetime escape/new authority path.

Final review: no outstanding Important finding. Twelve authored test API/JSON
assertions match inspected core definitions. Added revoked8 and actual16s idle8
admission tests, readonly annotations/shutdown. The specific lifetime crossing
DURING delivery has no targeted regression. No runtime/compilation claim.

Source whitespace check PASS. Rust tests, rustfmt, strict clippy, UniFFI generation
and Host/Android execution NOT_RUN in this environment. These do not authorize
production UI/PFD enablement. Parent's separate core verification is not this
adapter's runtime evidence.
