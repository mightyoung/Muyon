# Cross-owner adapter boundary — required before live card adoption

No patch below has been applied. These changes exceed the shell author's current
file ownership and need parent coordination with their owners. Existing UI remains
on its real native business confirmation/query controls in the meantime.

1. `product/chat/ProductChatRuntime.kt`, `product/agentipc/ProductService.kt`, and
   the trusted product/Rust owner need a bounded, versioned immutable component
   snapshot projection. Current ChatScreen data is request JSON plus native records;
   it is NOT a ComponentSnapshot/CardBinding. Expose original request/intent and
   stable message/component/attempt identities, actual workspace/conversation/project/
   agent scope, mounted generation, component/state revisions and the appropriate
   immutable host digest. Preserve absent/unknown facts. Do not add model-JSON
   callback dispatch or grant authority to a display DTO.
2. Receipt observations need their original identity separate from current card CAS.
   Unknown preserves actual held/charged fields (including null), exposes only original
   lookup and never creates a replacement request. Do not map an offline local PENDING
   submission to the card's execution-running status: local recording is not dispatch.
   A future trusted running observation may expose a local cancellation-intent event.
3. The shell adapter can then capture `pendingIdentity` and `expectedRevision` from
   the SAME displayed snapshot and call the fixed
   `requestCancel(scope, pendingIdentity, expectedRevision)`. A rejection stays
   rejected; do not fetch latest identity and retry. Dispatch, host cancellation
   authority and terminal receipt remain separate capabilities. Until that producer
   exists, combining the offline reducer is not production cancellation integration.
4. Attachment/evidence/material/report sources need actual stage facts, immutable
   document/source revision and anchor, snapshot membership and original-versus-
   current version facts. Do not fabricate versions, digests, claims, progress, or
   a saved receipt from existing display strings. Existing contract has no payload
   schema for these richer sources; an explicit trusted host projection is required.
5. Public source/document resolver interface should accept the neutral document ID,
   immutable version/anchor and calling business scope; research and supplier share
   the reader capability with separate authorization. No new PDF engine/SDK selected.
6. `ui/system` owner needs to neutralize actual used Material roles still defaulted:
   secondaryContainer/onSecondaryContainer and surfaceContainerLow (existing workflow
   chips/research panel). Shell consumes published colors rather than editing tokens.
7. Exact original brand asset placement needs coordinated resource ownership beyond
   MainActivity/ChatScreen/new shell Kotlin paths. Copy original bytes only from
   design archive400e206135690c284c8402521e3135cfb7bfaee8; do not generate replacements.

Required acceptance: real product Kotlin/Android test compilation, existing offline
regressions, authority/unknown/stale CAS tests, actual device captures/inspection,
large font/IME/Back/rotation/TalkBack, and independent review. No copied old device
result closes these gates. No backend write or live-provider retry is requested by
this plan.
