# Production gap implementation

Baseline: e16af808620488a7be0b3b4a10b91190d18f1177, latest merged develop observed through PR118 and local remote ref on 2026-10-23. PR108 remains draft at cb982e642496bae855c4bb10b71f8758a2843d60; its two PR workflows report success, and no GitHub review submissions are present. Workflow success does not close visual acceptance.

Implement in dependency order:

1. Add durable, namespace-isolated draft storage with CAS, SaveAck and original save-intent lookup. Connect the development conversation draft to it; test actual disk reopen and conflicting/retried saves.
2. Adapt existing ProductCore operations to HostCommandPort without a second command ledger or model-accessible confirmation. Verify original identity, confirmation, and recovery against the real owner.
3. Add the first real-provider repository response adapter using existing evidence reducers. Validate identity/SHA/check semantics with provider-shaped responses; keep actual OAuth/WebHook acceptance separate.
4. Re-evaluate remaining Skill/Connector/Reader execution gates against these changes. Do not invent new operations or permissions to hide a missing owner contract.
5. Verify changed behavior, strict lint and relevant integration tests; obtain independent review. Record exact tests and remaining real-provider, device and visual gates.

Known constraints: no new dependency requested; preserve original business schema and stopped live-model request routes; no connected Android device in escalated adb inventory. No automatic production mutations, OAuth enrollment or paid model canary. Existing macOS edits and unrelated worktrees remain untouched.

This plan authorizes no claim of complete production delivery. Each implementation step must have fresh evidence before being marked complete.
