# Presentation FFI handoff

Branch task/reader-evidence-ffi-20261022, additive to raw466424b13400c3f88b0cfec815ce3450c41b3cff.
Interface-first174b4be0 plus finalized selection fence in PRESENTATION-FFI-INTERFACE.md.
Core3ff95947337c85f15ef1f9edcf5d47ad49e14999/sourceee184fc1dd90faf2c3cdd48d735f47274de6d418;
purefmtdfa63451c0d65417b425f5bf1e92a3b43e0b6052 cherry-picked as6c5979f7.
Independent core evidencec68f1f1c59e859b6c87996f45cddae5c2baa8379 imported unchanged as e690b73f.
Those core original/formatted294 counts overlap and do NOT verify new FFI/Android.

## Native behavior

Seven additive methods, three typed records. No generated files/Host/Core ownership
edits. The native map retains actual nonconstructible PresentationTicket; wire
carries opaque ID and original frame generation. Exact scope/id/frame is checked
before core. Raw check/chunk/close refuse presentation mode. Stale frame callbacks
return DOCUMENT_PRESENTATION_STALE without native mutation, events or clear_all;
they never close/upgrade a newer frame. Only a successfully checked actual next
frame updates native ticket. EOF keeps actual presentation pin/snapshot/mapping,
session_active=true; old raw EOF remains false/closed. Loading is not displayable;
Ready is transferred raw bytes, not PDF parsing or rendering success.

Open fencing: begin_selection(scope) is called synchronously at the trusted
Service's actual authenticated selection event, BEFORE async source lookup.
Native creates one opaque token, bound to that scope,15s, consumed once before
core replacement. It is no grant and no wire counter proving current. Replaced,
expired, foreign-scope or replayed tokens fail before core can close current
presentation. Host must reject delayed selection events BEFORE native begin;
calling begin from a late callback would violate this protocol. Scope/principal
validation still belongs to Host, not a fabricated native identity mapping.

Cheap status and raw chunks never add is_current/full-file hashing. Core checks
fresh exact grant/head/pin/stamp and original snapshot. Frame activity retains
actual grant/absolute deadlines; checks do not renew idle. Native16MiB ceiling
remains; core64MiB total is snapshot payload, not RSS. No completion-size promise.

After every document-call success AND failure, drain core terminal notifications
into a<=8 native queue, mapping core lease IDs back to scoped native opaque IDs
BEFORE removing their mappings. No native lease ID/grant leaks to wire. Core queue
or native queue overflow, unmappable event, mismatched terminal generation, or any
global reader/evidence cleanup block sets clear_all. Mismatched event generation
covers N->N+1 advance failing before Host receives N+1. Trusted administrative drain
returns actual scope/id/generation so Service routes only to its matching client;
it is not an ordinary Messenger/model/client endpoint. Old async errors never
independently clear the current frame. A current-ticket denial, matching event or
clear_all does. Owner release/shutdown use stored genuine current tickets, not an
arbitrary stale page callback. Cleanup failure withholds output and requires real
cleanup/restart, never fake success.

## Test/review status

23 authored tests total: original12,9 added real temporary BusinessStore/grant/file
API tests,2 simulated notification/error projection tests with real native tickets.
New behavior includes EOF retention/raw isolation, stale old close/check/chunk/
advance fencing, replacement/scope, post-EOF revoke, actual short grant expiry,
current-ticket owner cleanup, bounded overflow, late same/cross-scope open/replay.
Two simulated cases cover unpublished next-frame terminal generation and global
reader/evidence cleanup flag propagation. They do not force an actual core cleanup
fault/post-increment race and must not be called runtime security evidence.

Test-first attempts and final native/full-workspace/fmt/clippy attempts retain
NOT_RUN127 because cargo is absent here. No behavioral RED/GREEN, generated
UniFFI, Android/PFD or renderer test is claimed. Original reports/logs are retained.
Source check manifest separately verifies five draft bodies/signatures unchanged,
mode dispatch/no redundant full hash, core purefmt byte equality and evidence SHA.
Independent static review original2notification findings and repairs are preserved.
The earlier12FFI pass reported by parent belongs to pre-presentation combination,
not this new source. B's sealed old FFI purefmta5acfba1cc87db348c9078313e0f84bb361e0590 was
partially reconciled AFTER5a7a2add: lib/bridge accepted under exact literal-aware
source equality; test candidate rejected and whole test file kept unchanged.
Proof/harness/rejection are in evidence/presentation-format-*. New source still
requires B's actual formatter/bindings, not old db40 bindings. No separate formatter
task was started or global lint allow added. Follow-up independent FORMAT-ONLY
review hit model capacity and is NOT_RUN; source behavioral review remains as above.

## Host/B acceptance still pending

B alone adds pending core exports if needed and generates/compiles new bindings.
The three new records and seven method signatures in protocol must be consumed
exactly. Host must serialize actual selection registration, validate current
principal/scope/project, carry original token and frame generation through async
work, anchor deadlines to request start, check before render/result publication,
poll check_after_ms<=1000, and drain notifications on success/error. Clear_all
requires actual PFD/bitmap/cache disposal by Host: core cannot retract copied OSFD.

No PFD, fake URI, policy grant, login, current-client identity join, page count,
PDF rendering, annotation mutation/original intent journal or engine/model/search
request is created here. Product reader remains unaccepted until real Host/PFD/
lifecycle integration and new-source Rust/UniFFI/Android validation complete.
Historical unknowns/reservation untouched; main/develop unchanged.
