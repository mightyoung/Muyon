# REG-2a Mac execution evidence

Branch: `task/reg-2a-outbound-tool-ledger`.
Base: `3ab20f09b1acd6252fb4ac970d1bc439d6b0b93f`.
Execution: macOS, `/Users/muyi/Downloads/dev/muspace/.claude/worktrees/reg-2a-outbound-tool-ledger`.
Original checkout observed at start: `/Users/muyi/Downloads/dev/muspace`, `task/p0-j3-doctor-tests`.
Remote: `https://github.com/mightyoung/Muyon.git`.
Original untracked files were left untouched. During this task, other work independently moved the primary checkout to task/folio-bypass and introduced tracked changes there; none was copied into or modified by this task. No AGENTS.md or .agents/skills exists in the task branch; checked parent instruction locations too. Usage-limit lookup failed; available quota cannot be verified.

## Implementation

Migration **9**, `outbound-tool-requests`, `foundation-v9`:
`apps/muyon/lib/workspace/workspace_repository.dart:145`.
New table and transaction: `apps/muyon/lib/platform/outbound_tool_ledger.dart:17`, `:28`, `:114`.
Pending commits before entering the transport callback; a failed INSERT prevents every send. Standalone managed connections used by the unchanged existing tests install the same table inside the pending transaction. There is no no-op host ledger. Completion writes succeeded/failed/cancelled plus finished_at. A completion-write failure propagates; it cannot retroactively unsend bytes and leaves pending as evidence of an unknown outcome. task_id is nullable; these adapters currently have no authoritative task ID binding.

Destination keeps scheme + host + port + path only, stripping userinfo/query/fragment and using P0-S2 maskedEndpoint. Errors pass redactCredentials/redactEndpoint; hub and transfer use fixed safe codes because remote errors can echo secrets unavailable to their authority. Digests are SHA-256 of the actual body/datagram. bytes_sent counts body bytes accepted by the HTTP send stream or UDP send return count, excluding headers, TLS framing and received bytes. It is not a promise of remote delivery. GET uses the empty-byte digest and zero bytes.

| Channel | Pending boundary / actual send accounting |
| --- | --- |
| MCP | `apps/muyon/lib/platform/mcp_adapter.dart:345`; initialize, notifications/initialized, tools/list, tools/call share _post. Complete JSON-RPC envelope bytes; HTTP failures, malformed/mismatched/error/isError replies fail the row. Timeout completes the row before returning. |
| inquiry_web | `apps/muyon/lib/app/inquiry_web_authority.dart:120`; pending precedes the trusted operation including DNS and GET; each redirect hop enters authority separately. No request body, so zero bytes. Production public-HTTPS/SSRF controls unchanged. |
| inquiry_hub | `apps/muyon/lib/app/inquiry_hub_authority.dart:120`; actual native body accounting `packages/supplier_core/lib/src/hub.dart:412`, callback `hub_channel.dart:39`. Canonical UTF-8 body, empty GET body. |
| transfer | `apps/muyon/lib/services/public_services.dart:79` supplies **tools.database (main host DB)**, not public_knowledge; `transfer_service.dart:662` passes the ledger to LanNode. `packages/supplier_core/lib/src/lan.dart:212` awaits pending, UDP helper `:250`, broadcast `:456`, discovery reply `:536`, /hello identity/certificate response `:582`, empty status responses `:619`, probe GET `:878`, HTTPS push `:964`. All node.push callers including task envelopes and chat delivery acknowledgements use that boundary. |

transfer.export/import only read/write local packages and receipt/import state; they do not initiate network sends. transfer.stop cancels timers, closes sockets and drains existing work without creating a new payload, so no new outbound row is appropriate. transfer.listen is **not exempt**: immediate/periodic broadcasts, discovery replies and /hello identity responses are all accounted. Empty acknowledgements/refusals also require pending; their empty-body digest and bytes_sent=0 exclude HTTP headers. A failed response pending write destroys the detached socket without sending headers. Listener replies explicitly use transfer.listen rather than probe/send.

## Verification

No existing test files changed. No outbound_requests, model gateway, module_api, registry, activation or UI files changed.

- `flutter analyze --no-pub` (apps/muyon): exit 0, raw line `No issues found! (ran in 139.8s)` (`analyze-delivery.log`). Earlier info failures are retained.
- New tests including empty listener refusals: exit 0, `00:31 +20: All tests passed!` (`new-tests-response.log`); the final restored combined run is in restored-delivery-tests.log.
- Restored final new tests + unchanged outbound_ledger_test, mcp_token_redaction_test, inquiry_web_authority_test, inquiry_hub_authority_test: exit 0, `00:25 +117: All tests passed!` (`restored-delivery-tests.log`). Earlier 116-test evidence is retained in restored-and-required-tests.log.
- Final host full flutter test: exit 1, `04:57 +777 ~3 -1: Some tests failed.` (`host-delivery-full.log`). Earlier complete run: `02:01 +776 ~3 -1: Some tests failed.` (`host-full-test.log`). The only failure is the existing task_events_test.dart:99 hardcoded expectation that schema version is 8; actual version is 9 as this task requires. The three skips are existing test settings. This is an unresolved validation gate; no existing test was edited to conceal it. host-full-final.log is an interrupted intermediate repeat and is **not** a completed full-test result (its Flutter shutdown reported EXIT_CODE=0 despite interruption). Final source-code full-test results are in host-delivery-full.log, run with concurrency=2 after all mutations and code changes ended.
- `dart analyze` (supplier_core): exit 0, `No issues found!` (`supplier-analyze-delivery.log`).
- LAN regressions lan_security_test/lan_trust_test/share_test: exit 0, `00:28 +26: All tests passed!` (`lan-regression-delivery.log`).
- Source/report diff whitespace check (apps, packages, scripts, REPORT.md): exit 0. The full staged diff whitespace check reported trailing spaces in captured raw Flutter logs. Those bytes are intentionally preserved as original evidence, so the raw-log whitespace findings are not hidden or normalized.

Initial SDK sandbox/cache errors, proxy WebSocket failure, new-test setup/compile failures, all analysis failures and all three mutation rounds are retained in this directory. Test servers use real loopback HTTP/TLS/UDP; fixtures do not prove real external-service or model integration.

## Mutations

`scripts/verify_reg2a_mutations.py` skips both begin and finish for exactly one channel while leaving approval/receipt writes and real transport code intact. Only outbound_tool_requests INSERT is denied by a BEFORE INSERT trigger. Thus this does not falsely pass due to an unrelated approval/receipt failure. Source is restored in finally, and restored tests passed.

| Channel | Real requests observed after bypass | Mutation exit | Result |
| --- | ---: | ---: | --- |
| mcp | 3 | 1 | killed |
| inquiry_web | 1 | 1 | killed |
| inquiry_hub | 1 | 1 | killed |
| transfer | 1 | 1 | killed |

The mutation logs contain REG2A_BLOCKED counts and assertion failures, and mutation-summary.log contains the exit/result matrix. Extra successful tests verify byte digests/lengths for Chinese + emoji, native hub POST, transfer push to TLS loopback, transfer main DB isolation, UDP datagrams, blocked listener identity reply, closed DB, cancellation and MCP timeout. Success HTTP servers observe pending before accepting the request body.

## Delivery / remaining limits

Commit and ordinary push are authorized only for this task branch; no merge, force push or develop/main push. Final response records the full commit SHA and verbatim equality check against git ls-remote. GitHub Actions ci triggers automatically for task/** pushes; the final response gives the actual queried CI state. No CI success is implied by a local result. Main full-test gate remains blocked by the version-8 assertion, which cannot be repaired under the instruction not to modify existing tests.

## Changed-file inventory

- `apps/muyon/lib/app/inquiry_hub_authority.dart`
- `apps/muyon/lib/app/inquiry_web_authority.dart`
- `apps/muyon/lib/platform/mcp_adapter.dart`
- `apps/muyon/lib/platform/outbound_tool_ledger.dart`
- `apps/muyon/lib/services/public_services.dart`
- `apps/muyon/lib/services/transfer/transfer_service.dart`
- `apps/muyon/lib/workspace/workspace_repository.dart`
- `apps/muyon/test/outbound_tool_ledger_test.dart`
- `docs/verification/REG-2a/REPORT.md`
- `docs/verification/REG-2a/analyze-delivery.log`
- `docs/verification/REG-2a/analyze-final.log`
- `docs/verification/REG-2a/analyze-initial.log`
- `docs/verification/REG-2a/analyze-passed.log`
- `docs/verification/REG-2a/format-final.log`
- `docs/verification/REG-2a/format-lint.log`
- `docs/verification/REG-2a/format-response.log`
- `docs/verification/REG-2a/format-tests.log`
- `docs/verification/REG-2a/format-tool-id.log`
- `docs/verification/REG-2a/format.log`
- `docs/verification/REG-2a/host-delivery-full.log`
- `docs/verification/REG-2a/host-full-final.log`
- `docs/verification/REG-2a/host-full-test.log`
- `docs/verification/REG-2a/lan-regression-delivery.log`
- `docs/verification/REG-2a/lan-regression-tests.log`
- `docs/verification/REG-2a/mutation-inquiry_hub-initial.log`
- `docs/verification/REG-2a/mutation-inquiry_hub-second.log`
- `docs/verification/REG-2a/mutation-inquiry_hub.log`
- `docs/verification/REG-2a/mutation-inquiry_web-initial.log`
- `docs/verification/REG-2a/mutation-inquiry_web-second.log`
- `docs/verification/REG-2a/mutation-inquiry_web.log`
- `docs/verification/REG-2a/mutation-mcp-initial.log`
- `docs/verification/REG-2a/mutation-mcp-second.log`
- `docs/verification/REG-2a/mutation-mcp.log`
- `docs/verification/REG-2a/mutation-summary-initial.log`
- `docs/verification/REG-2a/mutation-summary-second.log`
- `docs/verification/REG-2a/mutation-summary.log`
- `docs/verification/REG-2a/mutation-transfer-initial.log`
- `docs/verification/REG-2a/mutation-transfer-second.log`
- `docs/verification/REG-2a/mutation-transfer.log`
- `docs/verification/REG-2a/new-tests-corrected.log`
- `docs/verification/REG-2a/new-tests-direct.log`
- `docs/verification/REG-2a/new-tests-final.log`
- `docs/verification/REG-2a/new-tests-initial.log`
- `docs/verification/REG-2a/new-tests-passed.log`
- `docs/verification/REG-2a/new-tests-response.log`
- `docs/verification/REG-2a/new-tests-restored-final.log`
- `docs/verification/REG-2a/new-tests-restored.log`
- `docs/verification/REG-2a/pub-get-authorized.log`
- `docs/verification/REG-2a/pub-get.log`
- `docs/verification/REG-2a/restored-and-required-tests.log`
- `docs/verification/REG-2a/restored-delivery-tests.log`
- `docs/verification/REG-2a/supplier-analyze-delivery.log`
- `docs/verification/REG-2a/supplier-analyze.log`
- `packages/supplier_core/lib/src/hub.dart`
- `packages/supplier_core/lib/src/hub_channel.dart`
- `packages/supplier_core/lib/src/lan.dart`
- `scripts/verify_reg2a_mutations.py`
