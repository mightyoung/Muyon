# Offline response-header repair

## Evidence and boundary

The authorized followup ran source
`6f1fcb11e63f9ef04c51e2e8c59b4425eaec5f02`. Its first ordinary Send wrote one
POST and read HTTP/1.1 200, then recorded HTTP_HEADERS/unknown. No complete
response, candidate or usage was accepted. Raw headers were not retained;
the exact rejected header or read failure is unknown. This repair addresses
demonstrable parser defects, not a proved diagnosis of that live failure.
The stopped campaign, reservations and native records remain unchanged.
No real request, credential loading, APK upgrade or stopped-batch reset is part
of this repair.

## Short design before implementation

Retain the existing transport, socket, owner, cancellation, deadline and byte
bounds. Validate field names against ASCII tchar. After bounded syntax checks,
discard unused fields and allow their legal repetition; do not store or combine
Set-Cookie. Retain only framing and content-decoding metadata. Continue rejecting
duplicate Content-Length/Transfer-Encoding, CL+TE, unsupported transfer coding,
invalid/overflowing lengths and forbidden trailers (including Content-Encoding,
which now participates in decoding policy). Reject repeated or unsupported
Content-Encoding; only absent/identity is supported. Trim OWS as SP/HTAB only.
Trailer names use the same tchar validation. No new dependencies or interfaces.
The existing ASCII-only value subset remains a documented compatibility limit.

Primary references: [RFC 9110 field names and token grammar](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.6.2),
[repeated fields and Set-Cookie](https://www.rfc-editor.org/rfc/rfc9110.html#section-5.3),
[RFC 9112 field syntax](https://www.rfc-editor.org/rfc/rfc9112.html#section-5.1),
[message framing](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3).

## Verification contract

Keep all existing 68 socket-free checks. First demonstrate RED for legal repeated
unused fields and legal token names against the previous source, then GREEN
after repair. Add strict framing/encoding, malformed names, OWS and bounds cases.
Obtain independent design/source review. This is offline compatibility evidence;
it cannot establish provider acceptance or settle either unknown request.

## Implementation and evidence

Only OrdinaryChatHttpsTransport.kt and the existing JVM protocol test changed.
There are no owner, budget, search, binding, Rust or credential changes.
The existing line reader still bounds/validates every unused field before discard.
Content-Encoding trailers are rejected in either case spelling, in addition to
the original forbidden trailers. Non-ASCII field values remain unsupported.

Command (from the isolated worktree):
`sh experiments/redesign/android-compose-lab/checks/run_ordinary_chat_https_transport.sh`.

| Verification | Result |
| --- | --- |
| New legal-repeat test against previous parser | RED, exit1 at test163; original68 checks passed first |
| First repaired parser | PASS100, exit0 |
| Review-required Content-Encoding trailer guard, two negative cases | PASS102, exit0; original68 explicitly checked before additions |
| diff whitespace check | PASS, exit0 |
| Independent design review | CLEAR; required CE-trailer guard implemented |
| Independent final source/doc review and actual runner | APPROVE/CLEAR; PASS102, exit0; diffcheck exit0 |
| Android rebuild/lint/device run for this parser repair | NOT RUN; JVM compiled production transport directly; prior6f device/build evidence remains separately scoped |
| Real request or stopped-package upgrade after repair | NOT RUN, current campaigns stopped |

New checks include repeated Set-Cookie/Vary (also mixed case), complete tchar
names/underscore, OWS, legal trailers, malformed names/control/non-ASCII values,
header bounds, duplicate framing/decoding metadata, CL+TE and unsupported CE.
The old cancellation, late-read, authorization, write/read bounds, phase/status
and secret-redaction assertions remain. No test opens a socket or uses a real key.

Independent review confirmed the original68 checks remain before the34 additions,
all ignored fields are validated/bounded before discard, and TLS/single-write/
deadline/cancellation/key wiping/no-retry code is unchanged. It also verified the
result documents consistently report two unknown handoffs, two stopped batches,
no accepted answer/usage and2620 micro-CNY retained. Approval covers this offline
source and factual evidence only; it does not authorize a new live campaign.
