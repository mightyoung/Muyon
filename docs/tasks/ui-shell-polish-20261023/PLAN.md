# UI shell polish: approved scope

Base: `7aa852ab8134545c6312cd71de5c12cd49f66b5b`.
Design: `400e206135690c284c8402521e3135cfb7bfaee8`, UI v1.0 diagrams 01/02/08 and their written requirements. Bot diagram 06 remains a proposal; this slice only clarifies the existing four host steps.

1. Give the header conversation menu its own anchor and accessible name. The input plus opens a separate, unavailable attachment surface until a real host capability exists. Retain every original conversation action, permission check and request identity.
2. Put credential and cumulative-budget fields before detailed settings prose. The baseline already scrolls; this is a discoverability improvement, not a claim that scrolling was absent. Keep scrolling, price-proof warnings, accounting, input filtering, confirmation and credential clearing.
3. Render the actual main/pinned conversations in a horizontal top rail, with ordinary conversations below. Preserve selection, pin callbacks, empty state and original brand resources; no new conversation or transcript facts.
4. Show the existing Bot steps in Chinese and explain in-memory changes plainly. Do not add a proposal-only fifth step or enable persistence/creation/execution.

Owned production files: `product/chat/ChatScreen.kt` and `product/ui/shell/`. Tests: `ConversationShellTest.kt`. Existing foundation tokens and host contracts remain the source of truth. No public service API, Reader Core, native, Service, configuration-owner or agent-owner changes.

Validation: capture behavioral RED before production changes; compile the actual Android sources and all androidTest sources, run lint and neighboring offline checks, run exact shell component sources on the existing task-owned API26 x86_64 software emulator, then independent review. Component fixture results do not prove a new complete product APK or end-to-end backend capability.

Deferred: menu search/new-session/settings footer callbacks need a separately reviewed UI wiring slice; this slice does not invent inert buttons. Plugin-page design convergence, actual card facts/actions, controlled document capabilities and the proposed Bot/group flows remain separate work. Screenshots and the prior audit are retained locally; no disclosure/upload is included.
