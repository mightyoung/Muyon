# Fixed failure diagnostics after unknown

Scope: offline-only improvement following the first real unknown. The original
stopped batch, reservation and app data remain intact. No new provider request,
credential transfer, new batch or retry is authorized by this implementation.

Preserve the original fixed public error and no-cause exception. Add only a fixed
phase enum and an optional strictly parsed HTTP status integer (100..599) to the
internal HTTPS failure. Never retain exception messages/causes, TLS peer text,
response headers/body, payload, credentials or provider error text. Preserve inner
typed phases when crossing the outer transport boundary. Phases describe where
an exception occurred; WRITE does not prove delivery to the provider.

The same owner tracks handoff, post-response authority, validation and candidate
persistence phases. After stopping the durable budget, best-effort persist one
bounded, atomic app-private failure record per admission. It contains version,
SHA256 admission identity, fixed phase, optional HTTP status and UNKNOWN outcome.
Diagnostic I/O failure must not weaken the stop or alter the return value. Failure
evidence is not a settlement, usage record, receipt or authority to resend.
Do not overwrite a prior record when an already stopped admission is queried.
Only record once an actual permit was handed into the existing exchange path.

No public interface, Rust, owner callback, generated bindings or search changes.
The additional file is separate from candidate evidence and budget ledger.
No filesystem migration or reconstruction of the previous discarded cause.

Verify with socket-free tests for phase/status, hostile exception redaction,
one write/no retry, malformed input, cancellation and existing 27 protocol checks;
Android owner tests assert durable stop/retained reserve, safe diagnostic contents,
diagnostic-write failure isolation, and no resend after unknown. Run compile/lint
and selected device tests only against the no-INTERNET liveFixture package.
Independent review must check phase transitions and unchanged safety gates.

Independent architect design CLEAR and final SOURCE APPROVE received. Review
confirmed typed-stage preservation, no secret/raw cause retention, stop before
best-effort I/O, no diagnostic on repeated stopped calls, immutable first record,
unchanged public/Rust/generated/search surfaces. Reviewer independently ran all
68 HTTPS checks. Initial compile/lint passed42s, 0 errors/15 warnings; budget11
groups and reference4 fixtures passed. These are offline checks, not a diagnosis
of the already discarded first real failure or permission for another Send.
