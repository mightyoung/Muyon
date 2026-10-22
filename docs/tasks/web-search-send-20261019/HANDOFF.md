# WebSearch settings and ordinary Send handoff

Draft PR99: https://github.com/mightyoung/Muyon/pull/99, base `feat/deepseek-web-search` (PR98). Executable source: `590fbc026b2fc5d200236d1877482b03752d0d8f`. This document/evidence seal changes documentation only; runtime byte equivalence must be checked against that full source SHA before delivery. PR98 remains stacked on unmerged PR97; no main/develop merge or deployment.

## Implemented boundary

Private local settings UI defaults disabled/unconfigured and saves only provider/connection reference plus a fresh53-bit generation, never plaintext keys or arbitrary credential input. Save cannot invoke a model/search/probe. Main has no connection catalog or real SearchHost and honestly displays unconfigured/notready. Enabling without a host fails through the existing Service path, without ordinary-chat fallback or a fabricated response. Disabled keeps the inherited ordinary route; corrupt settings fail closed.

Ordinary Send uses frontendSubmit→existing Binder submitOrdinaryChat→admitted Service worker→provider-neutral RegisteredChatRoute→Catalog/Enrollment/SearchRuntime→actual core Agent. No new probe entry or second queue. Admission freezes route/config/query; repeated request identities cannot reprepare or resend. Generic native result verification and provider outbound verification bind original request/run/epoch/task/attempt/query/call/config/handle/currency/cap. Passive restore validates only stored evidence; changed settings, missing/tampered evidence and lost disclosure hide answer/source/cost/receipt without replay. Sources remain tainted with instruction_authority=false and are shown as text, with no automatic URL/icon fetch.

Only the isolated `searchFixture` build installs a socket-free fake host. The isolated variant and two named instrumentation tests are wired to exercise ordinary Settings→Send, the actual DeepSeek wire encoder/decoder and existing Agent path for nonempty sources, empty success and controlled error; cost is visibly synthetic. Main/debug/release do not install this host. Rust Service→Agent composition and pure state checks pass locally; the Android Settings→Send end-to-end gate remains pending this exact CI. Production WebSearch availability is not established.

SearchHost is still the explicit integration boundary for a real owner/TLS/credential/budget implementation. Real chat owner/TLS/CNY budget/credential bridge remains MacCodex-owned; its callback files and denied operation were not taken over. No real account/config/key/model/SearchHost/Fetch/paid call was touched, and the separate CNY1 chat budget was not used. Real service and physical device validation: NOT_RUN.

## Review and evidence

Independent short-design and immutable source review completed; final small diff at full executable SHA approved. Independent final build/test harness inspection found no additional issue. Reviewer did not rerun tests or obtain raw logs/artifacts. See REVIEW.md and DESIGN.md for corrections.

Exact-source local32Rust checks (contract5 +agent_search20 +service_send7),13 pure Kotlin checks, bridge build and genuine binding byte comparison passed. Commands and logs are under evidence/. Initial generator PATH failure is preserved; corrected generation and cmp succeeded. Local Android APK/lint/instrumentation: NOT_RUN (SDK/device absent).

Dedicated CI: https://github.com/mightyoung/Muyon/actions/runs/39279706227, attempt1, exact executable SHA. Current status: QUEUED; no runner assigned to scoped118151518829, x86_64 producer118151519184 or arm64-v8a producer118151519304. Package/device job depends on those jobs and has not run. No CI or API26 pass is claimed. Only new targets/build-only producers and the two explicitly named synthetic device tests are eligible; no old aggregate/I04 was run. No old403 resource was fetched or retried. CI was not cancelled/rerun.

## Remaining gate

Wait for this exact CI run's terminal metadata. If it fails, diagnose only that new run's permitted evidence; stop if denied/403. Any source fix requires a new exact immutable SHA, source review and new dedicated CI. If it succeeds, scope the claim to32Rust/13Kotlin/genuine binding, dual API26 ABI production, APK/lint and the two named synthetic Settings→ordinary Send tests. Never infer real SearchHost, billing, owner/TLS or physical-device completion. Keep draft/stacked dependencies and PR86 HOLD; do not merge or deploy.

Remote safety check: main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`, develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`, PR86 `3f1be180bb009a91e659c113ba5b1916e5360332`, PR97 `3abc1cae405de4c941d540f1043cdf31463b3f95` unchanged at this check.
