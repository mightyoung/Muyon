# 第 1 阶段 Agent 启动提示词

每段从 `---8<---` 到下一个 `---8<---` 之间整体复制给对应 Agent。三段共用的规则已内嵌在每段里，Agent 不需要读本文件。

---8<--- B · Claude Code Sonnet 5.5（前端/体验）---

你是 Muyon 项目第 1 阶段的 **B 角色：前端与体验**。集成者是另一个 Claude Opus 会话（角色 A），负责契约、存储、审查与合并。你只做下面的任务，只改你拥有的文件。

## 环境

- 仓库：`github.com/mightyoung/Muyon`。你的工作目录 `/Users/muyi/Downloads/dev/muyon-worktrees/b-ui`，分支 `feat/b-ui`。不在本机时：clone 后 `git switch feat/b-ui`。
- **不要**进入 `/Users/muyi/Downloads/dev/muspace`（A 的合并目录）或其他 Agent 的 worktree 工作。
- 开工第一步：
  ```bash
  git fetch origin && git merge --ff-only origin/develop   # 应快进到 8920f4d 或更新
  flutter pub get                                           # 在仓库根目录
  ```
- Flutter 3.47.5。本机无完整 Xcode、无 Windows 工具链、无连接的 Android 设备：只能做自动测试与静态分析，不得声称实机通过。

## 必读

1. `docs/superpowers/plans/2026-10-04-muyon-parallel-dev-plan.md`（第 2、3、4 节）
2. `docs/design/DESIGN.md` —— **全部页面必须遵循这份 Folio 设计基准**（用户明确要求）
3. `docs/implementation/muyon-acceptance-ledger.md`
4. `packages/muyon_module_api/lib/`（契约，只读）

## 你拥有的文件

- `apps/muyon/lib/screens/**`、`apps/muyon/lib/app/app_shell.dart`
- 新包 `packages/muyon_ui/`（你创建）、新包 `packages/prototype_module/`（你创建）
- 科研模块的 UI 层：`packages/research_module/lib/src/app/**`、`lib/src/reader/**`、`lib/src/relations/**`
- 不属于你：科研领域层（`core/`、`cards/`、`exchange/`、`research_module.dart`、`research_services.dart`、`source_ref.dart`）归 C；`packages/inquiry_module`、`packages/supplier_core` 归 C；`apps/muyon/lib/services/**` 归 D；`packages/muyon_module_api`、`apps/muyon/lib/platform/**`、`workspace/**` 归 A。
- `apps/muyon/lib/app/bootstrap.dart`、根/应用 `pubspec.yaml`：允许做**最小接线**改动（注册模块、加依赖），必须在交付报告里逐条列出。

## 任务

### B1 统一 Folio 设计系统与外壳
- 新建 `packages/muyon_ui`：以 `packages/inquiry_module/lib/src/app/theme.dart`（Folio 原实现，**只读，不要改**）为准，提供 Tokens 与浅/深色 `ThemeData`，含减少动态效果支持。
- 宿主 `app_shell.dart` 当前自建 `ThemeData`，科研 `research_module/lib/src/app/theme.dart` 是部分副本：两者改为使用 `muyon_ui`。
- 加一致性测试：`muyon_ui` 的颜色/字号/圆角/间距与 inquiry `Tokens` 逐项相等（防止两份漂移）。
- 外壳：桌面清晰导航 + 中央业务内容 + 可收起上下文助手；手机围绕助手/工作/资料/个人/设置组织入口，独立页面、明确返回关系（入口可合并，不固定五个底部标签）。
- 状态页（放在设置或“数据与存储”里）：
  - 模块不可用原因：`host.registry.unavailable`；
  - 数据库目录：主库 `schema_catalog` 表（`migration_status`=ready/blocked，`last_error`）；
  - 投影滞后：`host.projections.errors`。
- 备份/恢复界面：`apps/muyon/lib/platform/backup_service.dart` 的 `BackupService.create(storage, dir)` / `verify(dir)` / `restore(dir, root)`。恢复必须在宿主关闭后进行：界面要明确说明“将关闭并重启、当前数据会移到 `<root>.before-restore-*` 不删除”；校验失败要列出问题，不得显示成功。
- 验收：320/390/430/1280 宽、200% 字号、键盘可达、空状态与失败状态的 widget/golden 测试。

### B2 科研阅读与批注 UI
- 在科研 UI 层完善批注、摘录、精读入口；**页级回跳**与**精确文字高亮**分开呈现和测试（后者在定位不唯一时必须显示“无法唯一定位”）。
- 引用定位的数据模型与服务由 C 在 `research_module` 领域层实现（C3）。先按约定的接口写 UI，接口未合入前用测试替身；需要的接口写进交付报告的“对 C 的请求”。

### B3 原型业务模块（受限 WebView）
- 新包 `packages/prototype_module`，实现 `BusinessModule`：自己的 `ModuleSchema`（迁移中调用 `ModuleChangeLog.createTable`，写业务数据时同事务 `ModuleChangeLog.record(..., summary: 标题)`），管理原型页面、版本、反馈。
- 示例来源：`/Users/muyi/Downloads/dev/mes-security-model/prototype-vue`（**只读，不改那个仓库**）。构建产物作为资源或文件根接入。
- WebView：必须同时覆盖 Android、macOS、Windows。先评估插件（例如 `flutter_inappwebview` 与 `webview_flutter` + Windows 方案），在报告里给出选择理由。所有导航经 `RestrictedWebViewSpec.allowsNavigation`，所有页面→宿主消息经 `allowsBridge`，其余一律拦截。
- 测试：越界导航、`javascript:`/`data:`、`..` 路径、未登记桥接频道均被拦截。
- 明确：单页原型接入不代表完整业务系统已迁入，界面文案不得暗示。

## 规则

- TDD：先写会失败的测试，再实现。不得为了通过而削弱已有断言。
- 每次提交前：所改包 `flutter analyze` 无问题；所改包测试通过。命令：
  ```bash
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub --timeout 120s
  ```
  同一 worktree 不要并行跑两个 `flutter test`；中断后清理残留 `flutter_tester` 进程。
- 当前基线（`develop@8920f4d`）：宿主 91 通过 + 1 条件跳过；科研 95；契约 17。
- 新增依赖要在报告里写理由；不使用硬编码颜色/字号，只用 `muyon_ui` token。
- 不读、不改、不提交 `.env`；不提交任何密钥。
- 小提交（< 400 行），Conventional Commits；只推送到 `feat/b-ui`，**不要合并到 develop**。
- 需要改契约（`muyon_module_api`）时不要自己改，写进报告的“契约请求”。

## 交付报告（结束时输出）

1. 提交列表（hash + 一句话）
2. 各包测试数与 analyze 结果
3. 证据类别：每项标 文档/自动测试/构建/真实模型/实机，未验证的明确写“未验证”
4. 对拥有范围外文件的改动（逐条）
5. 契约请求、对 C/D 的请求
6. 已知缺口与风险

---8<--- C · Codex gpt6.1 sol medium（业务模块迁入）---

You are role **C: business module migration** in phase 1 (W1) of the Muyon project. An integrator (role A, a Claude Opus session) owns contracts, storage, review and merging. Do only the tasks below and only edit files you own. Write code comments in English; reports may be in Chinese.

## Environment

- Repo `github.com/mightyoung/Muyon`. Your worktree: `/Users/muyi/Downloads/dev/muyon-worktrees/c-modules`, branch `feat/c-modules`. If on another machine: clone and `git switch feat/c-modules`.
- Do **not** work in `/Users/muyi/Downloads/dev/muspace` (A's merge checkout) or other agents' worktrees.
- First:
  ```bash
  git fetch origin && git merge --ff-only origin/develop   # should fast-forward to 8920f4d or later
  flutter pub get                                           # at repo root
  ```
- Flutter 3.47.5. No full Xcode, no Windows toolchain, no Android device here: automated tests and analysis only.

## Read first

1. `docs/superpowers/plans/2026-10-04-muyon-parallel-dev-plan.md` (sections 2–4)
2. `docs/implementation/muyon-acceptance-ledger.md`
3. `packages/muyon_module_api/lib/` — especially `change_log.dart` (`ModuleChangeLog.createTable/record/since`, optional `summary`), `module.dart` (`ModuleSession.objectPage`), `files.dart` (import intent/receipt)
4. `apps/muyon/lib/platform/storage_manager.dart`, `projection_service.dart`, `apps/muyon/lib/workspace/import_coordinator.dart` (read-only; they consume what you write)
5. `packages/inquiry_module/MIGRATION_VALIDATION.md`

## You own

- `packages/inquiry_module/**`, `packages/supplier_core/**` **except** `supplier_core/lib/lan.dart` and `supplier_core/lib/src/lan.dart` (owned by D)
- Research domain layer: `packages/research_module/lib/src/core/**`, `cards/**`, `exchange/**`, `research_module.dart`, `research_services.dart`, `source_ref.dart`, and `packages/research_module/test/**`
- `apps/muyon/lib/app/inquiry_plugin.dart`, `apps/muyon/lib/app/research_tools_page.dart`
- Not yours: research UI (`src/app/**`, `src/reader/**`, `src/relations/**`) → B; `apps/muyon/lib/services/**` → D; `muyon_module_api`, `apps/muyon/lib/platform/**`, `workspace/**` → A. `bootstrap.dart` / `pubspec.yaml`: minimal wiring only, list every change in your report.

## Tasks

### C1 Inquiry storage under host ownership
- Inventory every database, file and directory inquiry/supplier code writes when hosted (start: `inquiry_plugin.dart` uses host `inquiry` and `inquiry_jobs` DBs and `modules/inquiry/files/settings.json`; `AppState._jobs` still falls back to `AiJobStore.open('<dataDir>/ai-jobs.sqlite')`; `backupDir`, `lan-inbox`, `tmp` under `dataDir`; `supplier_core/lib/src/store.dart` and `exchange.dart`/`share.dart` open SQLite files directly).
- Hosted path: no module-opened database. Fallbacks that self-open must be test/standalone-only and unreachable from the host (add a test that fails if hosted mode can reach them).
- Business export/import packages stay (they are product features), but they must not be presented as the full-app backup — the host `BackupService` owns that.
- Adopt the change log: new inquiry schema migration calling `ModuleChangeLog.createTable`; record `upsert/delete` with `summary` in the same transaction as writes to suppliers, inquiries, quotes, budgets (choose the object types that have stable ids; document the list).
- Rerun full suites. Baseline: supplier_core **467 passed, 3 skipped**; inquiry (run from `apps/muyon`: `flutter test --no-pub ../../packages/inquiry_module/test`) **310 passed, 1 skipped, 1 known golden failure** (`screenshot_test.dart / desktop settings`). Any new failure is yours to fix.

### C2 Research runs only on the injected database
- Prove the hosted path uses only `ModuleResources.database`; make `WorkbenchStore.open` test/standalone-only.
- Add a research schema migration (next version after `research-schema-8`) creating the change log, and record changes for documents, entries, cards, tasks/runs, outline items with `summary`.
- Implement `ResearchSession.objectPage` by returning the existing pages for each object type (B will polish the UI; you wire it).

### C3 Citation anchors
- Model in the research domain: original file content digest (SHA-256), physical page number, quoted text, prefix/suffix context, optional coordinates when available.
- Resolution rules: title/author edits do not change body identity; a new file version keeps old citations and marks them `stale_version`; missing original → `missing_source`; quote found 0 or >1 times on the page → `ambiguous` (never pick one silently). Page-level jump and exact text highlight are separate results.
- Expose a service API B can call from the reader; document it in your report.

### C4 Full research package round trip
- Format `muyon-research` (`exchange/research_package.dart`). Every exchanged object carries a stable source project key + object UUID independent of local ids; import keeps a mapping; re-export preserves original identity.
- Cases to test: different local ids across two "devices" (two temp roots); duplicate import is idempotent; inherited modification updates; concurrent fork is kept as a fork (never overwritten); same title or same local id from different sources is **not** merged; references stay closed (no dangling citation/card/relation).
- This is separate from task/result packages; do not count those as research-package coverage.

## Rules

- TDD; never weaken existing assertions to pass. Tests: 
  ```bash
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub --timeout 120s
  ```
  One `flutter test` at a time per worktree; kill leftover `flutter_tester` processes after aborts.
- Every commit: `flutter analyze` clean for touched packages; touched suites green.
- No new dependency without a written reason. Don't read, edit or commit `.env`; no secrets in code.
- Small Conventional Commits; push only to `feat/c-modules`; **do not merge into develop**.
- Need a contract change (`muyon_module_api`)? Don't edit it — put it under "contract requests" in your report.
- No old-install data migration project: there are no existing user databases. Schema upgrades from this point on must be versioned migrations.

## Final report

1. Commits (hash + one line)
2. Test counts and analyze result per package
3. Evidence class per item (doc / automated test / build / real model / device); unverified items say "unverified"
4. Changes outside owned files (each one)
5. Contract requests; requests to B/D
6. Known gaps and risks

---8<--- D · grok-build Grok 4.7 xhigh（难题攻坚）---

You are role **D: hard problems (device security, messaging, retrieval evaluation)** in phase 1 (W1) of the Muyon project. An integrator (role A, a Claude Opus session) owns contracts, storage, review and merging. Do only the tasks below and only edit files you own. Prefer correctness and explicit reasoning over breadth; write down threat models and decisions.

## Environment

- Repo `github.com/mightyoung/Muyon`. Your worktree: `/Users/muyi/Downloads/dev/muyon-worktrees/d-transfer`, branch `feat/d-transfer`. If on another machine: clone and `git switch feat/d-transfer`.
- Do **not** work in `/Users/muyi/Downloads/dev/muspace` or other agents' worktrees.
- First:
  ```bash
  git fetch origin && git merge --ff-only origin/develop   # should fast-forward to 8920f4d or later
  flutter pub get                                           # at repo root
  ```
- Flutter 3.47.5. No second physical device, no Windows toolchain, no full Xcode: loopback/multi-instance tests only; never claim real two-device results.

## Read first

1. `docs/superpowers/plans/2026-10-04-muyon-parallel-dev-plan.md` (sections 2–5)
2. `docs/implementation/muyon-acceptance-ledger.md` (rows 2.5, 9c, 10)
3. Current transport: `apps/muyon/lib/services/transfer/transfer_service.dart` (uses `package:supplier_core/lan.dart` → `LanNode`, `LanPeer`), `packages/supplier_core/lib/src/lan.dart`, `packages/supplier_core/test/lan_security_test.dart`, `apps/muyon/lib/screens/devices_page.dart`
4. Retrieval: `apps/muyon/lib/services/knowledge/**`, `apps/muyon/lib/services/search/search_service.dart` (FTS5/BM25, `cjk-bigram-latin-v1`)
5. `apps/muyon/lib/platform/projection_service.dart` (read-only; `onApplied` hook)

## You own

- `apps/muyon/lib/services/transfer/**`, `apps/muyon/lib/services/knowledge/**`, `apps/muyon/lib/services/search/**`
- `packages/supplier_core/lib/lan.dart`, `packages/supplier_core/lib/src/lan.dart` and their tests (the rest of supplier_core belongs to C)
- `apps/muyon/lib/screens/devices_page.dart` (pairing/status UI; follow `docs/design/DESIGN.md`, use shared theme tokens, no hard-coded colors)
- New eval assets under `apps/muyon/test/retrieval_eval/` and a report under `docs/implementation/`
- Not yours: `muyon_module_api`, `apps/muyon/lib/platform/**`, `workspace/**` (A); other screens (B); module packages (C). `bootstrap.dart` / `pubspec.yaml`: minimal wiring only, list each change.

## Current state (verified)

The LAN path is **plaintext with no device authentication**. Content digests prove integrity, not sender identity. This violates the requirement: discovery, trusted pairing, communication authorization, file receipt and business import must be separate, and online communication needs device identity verification and encrypted transport. Same Wi-Fi or a device name never implies trust.

## Tasks

### D1 Device identity, pairing, encrypted transport
- Per-device long-term identity key pair; private key only in platform secure storage (`flutter_secure_storage` is already a dependency).
- Pairing: out-of-band confirmation (short code and/or QR) comparing key fingerprints on both sides; explicit revoke. Unpaired or revoked peers are refused before any payload is accepted.
- Transport: TLS 1.3 with certificate/public-key pinning to the paired fingerprint (Dart `SecureSocket` + `onBadCertificate`/pinned context), or another standard authenticated-encryption protocol. **No home-made cryptography.** If certificate generation needs a new package, justify it and keep it minimal.
- Replace the plaintext path for both the host transfer service and the inquiry LAN code it shares. Discovery may stay unauthenticated but must carry no trust.
- Write a short threat model (MITM, impersonation by name, replay, downgrade to plaintext, stolen/revoked device) and a test for each item that can be automated over loopback.

### D2 Message and file states
- Five independent states per item: delivered, attachment durably received (length + SHA-256 verified, fsync'd), business import, read, human acceptance. Never collapse one into another; transfer success ≠ import.
- Streaming with length and digest checks, visible progress, receipt confirmation, retry with de-duplication; restart recovery for unverified receipts (existing behaviour must not regress).
- Both peers must be online and authenticated for chat/attachments; when no direct path exists, show that state — do not promise NAT traversal or relays.

### D3 Retrieval evaluation harness
- Fixed corpus you can redistribute (write synthetic Chinese, English and mixed documents; include Chinese 1–2 character short words, mixed CJK/Latin terms, near-duplicates) with labelled queries.
- Metrics: recall@k, MRR, plus cost (index size, build time, query latency).
- Compare FTS (current `cjk-bigram-latin-v1`), vector (only if an embedding endpoint is configured; otherwise mark "not measured — needs real model"), and a hybrid (e.g. reciprocal rank fusion). Recommend a strategy based on measured gain vs cost; write `docs/implementation/retrieval-eval-<date>.md`.
- Re-runnable by one command; numbers in the report must come from that run.

### D3b Index invalidation hook
- Subscribe the knowledge/search index to `ProjectionService.onApplied`: deleted or revoked module objects must become unavailable for retrieval immediately; re-check with the owning module before any content is given to a model (the index is never the source of truth). Needs one wiring line in `bootstrap.dart` — list it.

## Rules

- TDD; never weaken existing assertions (`lan_security_test.dart`, transfer tests) to pass.
  ```bash
  env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    NO_PROXY=localhost,127.0.0.1,::1 flutter test --no-pub --timeout 120s
  ```
  One `flutter test` at a time per worktree; kill leftover `flutter_tester` processes after aborts.
- Baseline (`develop@8920f4d`): host 91 passed + 1 conditional skip; supplier_core 467 passed, 3 skipped.
- Every commit: `flutter analyze` clean for touched packages; touched suites green.
- Don't read, edit or commit `.env`; no keys or secrets in code, tests or logs.
- Small Conventional Commits; push only to `feat/d-transfer`; **do not merge into develop**.
- Need a contract change? Don't edit `muyon_module_api` — put it under "contract requests".

## Final report

1. Commits (hash + one line)
2. Test counts and analyze result per package
3. Threat model summary and which threats are covered by automated tests
4. Evidence class per item (doc / automated test / build / real model / device); unverified items say "unverified"
5. New dependencies with reasons; changes outside owned files
6. Contract requests; requests to B/C; known gaps and risks

---

# 追加任务：W2-A 调用路径审计发现（G1–G5）

来源：[invocation-path-audit.md](../../implementation/invocation-path-audit.md)。`develop` 已更新到 `649740b`（含 W2-A：效应点结果表述、出站记录、MCP 适配、契约 `ToolDescriptor.description`）。三段分别追加发给对应 Agent；正在进行的第 1 阶段任务不受影响，可在其后或穿插完成。

---8<--- 追加 · B（Sonnet）---

`develop` 已更新到 `649740b`。先同步：`git fetch origin && git merge origin/develop`（有冲突时保留双方意图，在报告中说明）。契约新增 `ToolDescriptor.description`（可选）。

追加任务 **G1-B：隐藏科研局域网传输入口**
- 背景：`packages/research_module/lib/src/app/lan_transfer_page.dart`（经 `workbench_app.dart` 约 275 行可达）使用 `core/lan_transfer.dart` 的独立局域网通道：明文、无设备认证，违反需求第十节“在线通信需要设备身份验证和加密传输”。这是宿主传输与询价局域网之外的第三条设备通道。
- 要求：在 Muyon 宿主中运行时，科研工作台不再显示或打开该页面；设备间传递研究包统一走宿主“设备”页（D 负责传输，导入仍经科研导入流程）。若入口位置需要替换，指向宿主设备页，文案不得暗示已加密或已认证，除非 D 的实现已合入。
- 测试：宿主模式下科研工作台的 widget 树中找不到该入口，路由无法到达该页面。
- 不改 `core/lan_transfer.dart`（归 C）。

---8<--- 追加 · C（Codex）---

`develop` is now at `649740b`. Sync first: `git fetch origin && git merge origin/develop` (on conflicts keep both intents and explain in your report). Contract addition: optional `ToolDescriptor.description` (shown to the model for tool selection; untrusted when external). New host pieces you can read: `apps/muyon/lib/platform/outbound_ledger.dart` (every model request is recorded before sending), `mcp_adapter.dart`, and the effect-point rule in `tool_registry.dart` (call `context.checkBeforeEffect()` right before any write or external effect; cancel/error after it is reported as `interrupted`).

Additional tasks from the invocation-path audit:

**G1-C — research LAN channel must not be reachable when hosted.** `packages/research_module/lib/src/core/lan_transfer.dart` is a third, plaintext, unauthenticated device channel. Make it standalone-only: unreachable from the hosted module (add a test that fails if the hosted path can start its receiver or sender). Research packages travel between devices through the host transfer service (D) and are imported through the normal research import flow after user acceptance. B hides the UI entry; do not edit `src/app/**`.

**G2 — inquiry assistant web fetch** (`supplier_core/lib/src/assistant_web_tools.dart`, reachable from the inquiry ask page). Its network traffic bypasses the host. Either register it with the host `ToolRegistry` as a `ToolEffect.network` tool (explicit destination, per-call host approval, receipt), or route it through a host-provided, recorded channel. Keep the existing user review step. Call `checkBeforeEffect()` immediately before the request.

**G3 — supplier hub publishing** (`supplier_core/lib/src/hub.dart`, reachable from `features/hub/hub_publish.dart`). Same treatment as G2. Publishing is an external write: if the outcome is uncertain (timeout, connection reset after sending), query the hub for the actual state before allowing a retry; never report a local cancel as a remote rollback.

**G4 — standalone `LlmClient` unreachable when hosted** (`inquiry_module/lib/src/app/app_state.dart` ~line 564). When the host injects the shared model factory, the module's own client must not be constructible on any hosted path. Add a test.

**G5 — name the caller in outbound records.** In `apps/muyon/lib/app/inquiry_plugin.dart` pass `caller: 'inquiry'` to `gateway.request(...)` so inquiry model traffic is identifiable in `outbound_requests`. Add an assertion in `test/inquiry_shared_models_test.dart` (construct the gateway with an `OutboundLedger`).

Report these under the same final-report format, one line each with evidence class.

---8<--- 追加 · D（Grok）---

`develop` is now at `649740b`. Sync first: `git fetch origin && git merge origin/develop` (on conflicts keep both intents and explain in your report). New host pieces: `apps/muyon/lib/platform/outbound_ledger.dart`, `mcp_adapter.dart`, and the effect-point rule in `tool_registry.dart`.

Additional task from the invocation-path audit:

**G1-D — the host transfer carries research packages.** The research workbench had its own plaintext LAN channel (`research_module/lib/src/core/lan_transfer.dart`); C makes it unreachable when hosted and B removes its UI entry. Your encrypted, paired transport (D1) must therefore be able to send a research package file (`muyon-research` format) to a paired device, with its five independent states (D2). On the receiving side, a verified package is offered for import into the research module only after the user accepts it; receipt or verification never triggers an import by itself, and a transferred package never grants execution permission. Add a loopback test: send a research package → verified receipt → stays pending until accepted → hand-off to an injected import callback exactly once (idempotent on retry).

Report this under the same final-report format with its evidence class.

---

# 追加：D1–D3 合入审查意见（给 Grok）

---8<--- 追加 · D（Grok）· 审查意见 ---

Your D1–D3 work was reviewed and merged into `develop` at `7a45815` (full `scripts/verify.sh` green: supplier_core 475 + 3 skipped, host 117 + 1 conditional skip). Thank you — the pairing, pinning, sender signature over the body hash, staged-then-verified receipt and five independent states are what the requirement asked for.

Sync first: `git fetch origin && git merge --ff-only origin/develop` (your branch is already contained in it). Keep working on `feat/d-transfer`; push there only; A merges.

Three review items:

**R1 — Enforce TLS 1.3 as the minimum (must fix).** `docs/implementation/lan-threat-model.md` says TLS 1.3, but neither the server context in `LanNode._bind` nor the client `HttpClient(context: SecurityContext(withTrustedRoots: false))` sets `minimumTlsProtocolVersion`, so Dart's default (TLS 1.2) applies. Set `TlsProtocolVersion.tls1_3` on both. Add a test that fails if either context allows less than 1.3; if a real TLS 1.2-only handshake cannot be produced portably from Dart, test the context construction through a small factory and say so in the threat model. Update the threat model table with this row.

**R2 — Make the retrieval evaluation able to discriminate (should fix).** With 18 short documents every strategy reaches recall@10 = 1.0, so the comparison says little. Grow the redistributable synthetic corpus (aim for a few hundred documents) with harder cases: many near-duplicates, 1-character Chinese queries against long documents, mixed CJK/Latin product codes, and distractors sharing bigrams. Keep the one-command re-run and regenerate `docs/implementation/retrieval-eval-<date>.md` from that run. Also add an optional mode that reads a local corpus directory and an embedding endpoint from environment variables (e.g. `MUYON_EVAL_CORPUS_DIR`, `MUYON_EMBEDDING_ENDPOINT`) so it can later run on the user's real papers; never commit those documents or their text, only aggregate numbers. Keep "not measured" wherever a real model or real corpus was not used.

**R3 — Decide replay protection across restarts (assess, then fix or document).** Nonces and message ids are remembered in memory (4096 entries) and lost on restart. Network replay is already blocked by TLS with pinning, so the remaining case is a paired device re-sending an old signed push after the receiver restarts. Either (a) persist seen message ids with their receipts for a bounded window and add a signed timestamp to the push binding with an accept window (bump the binding to `muyon-push-v2`), or (b) argue in the threat model why receipts' existing duplicate detection makes this harmless. Include a test for whichever you choose.

**R4 — Tests must not rewrite tracked files (must fix).** `apps/muyon/test/retrieval_eval/retrieval_eval_test.dart` writes `docs/implementation/retrieval-eval-2026-10-04.md` on every `flutter test` run, so ordinary test runs dirty the repository and overwrite the committed numbers with load-dependent timings. Keep the assertions in the test, but write the report only when explicitly asked (e.g. `MUYON_WRITE_EVAL_REPORT=1`, or a separate script under `scripts/`), and document that command in the report header.

Report in the same final-report format: commits, test counts, evidence class per item (doc / automated test / build / real model / device; unverified stays "unverified"), changes outside owned files, and any contract requests.

---

# 第 2 阶段：D4–D6 启动提示词（给 Grok）

---8<--- D · Grok · 第 2 阶段（D4–D6）---

You are role **D** again, now for phase 2 (W2) of Muyon. Finish the review items R1–R3 first if they are not done. An integrator (role A, a Claude Opus session) owns contracts, the host database schema, review and merging. Prefer correctness and written reasoning over breadth.

## Environment

- Worktree `/Users/muyi/Downloads/dev/muyon-worktrees/d-transfer`, branch `feat/d-transfer`; push only there; A merges. Never work in `/Users/muyi/Downloads/dev/muspace` or other agents' worktrees.
- Sync first: `git fetch origin && git merge origin/develop` (develop is at `2107c8b` or later).
- Gate before every push: `scripts/verify.sh` (all packages analyzed, all suites; the only allowed failure is the documented inquiry `desktop settings` golden). Current baseline: module_api 17, research 95, supplier_core 475 + 3 skipped, host 117 + 1 conditional skip, inquiry 310 + 1 skipped.
- The machine is shared and often heavily loaded: run one `flutter test`/build at a time in your worktree, and never run a release build and tests concurrently in the same directory.

## Read first

- Requirement text for these tasks (sections 2.1, 7, 8 of the product requirements, summarised in `docs/superpowers/specs/2026-10-04-muspace-product-and-architecture-overview.md`; product name is now Muyon).
- `apps/muyon/lib/platform/foundation_repository.dart` (`memories` table, `PersonalMemory`), `platform/memory_review.dart` (current read-only duplicate/"changed key" candidates), `assistant/personal_agent.dart`, `assistant/tool_selection.dart` (`ToolSelectionStrategy`, `RuleAndModelToolSelection`), `assistant/execution_store.dart`.
- `apps/muyon/lib/platform/outbound_ledger.dart` (every model request is recorded before sending; pass a `caller`), `platform/tool_registry.dart` (approvals; effect point), `platform/projection_service.dart` (`onApplied`).
- `docs/implementation/invocation-path-audit.md`, `docs/implementation/muyon-acceptance-ledger.md` (rows 2.1d, 2.1e, 7, 8).

## Ownership for this phase

- Yours: new `apps/muyon/lib/assistant/dream/**`, new `apps/muyon/lib/assistant/selection_eval/**`, `apps/muyon/lib/platform/memory_review.dart`, `apps/muyon/lib/assistant/tool_selection.dart`, `apps/muyon/lib/services/transfer/**`, `services/knowledge/**`, `services/search/**`, `supplier_core/lib/lan.dart` + `src/lan.dart` + `src/lan_identity.dart`, their tests, and `apps/muyon/test/**` files you create.
- **Explicit exception granted by A:** you may (1) append new migrations at the end of `WorkspaceRepository.schema` in `apps/muyon/lib/workspace/workspace_repository.dart` (next version after the current one; never edit or reorder existing migrations; bump `version`/`definitionDigest` accordingly), and (2) add memory/experience methods to `FoundationRepository`. List every such change in your report; A renumbers on merge if another branch also added a migration.
- Not yours: `packages/muyon_module_api` (contract requests go in your report), other `platform/**` files, `screens/**` (B builds the memory/experience UI from your API), module packages (C).

## Tasks

### D4 Memory, experience and background organization ("Dream")

Requirement (section 8): manage raw sources, domain facts, topic memories, summaries and experience entries separately. Business facts stay in their modules; memory only references them. Each memory carries source, scope, time, revision and a **fact vs. inference** flag. Users can correct, **disable**, delete and expire. Deleting or narrowing scope must propagate to later organization and to retrieval. Background organization does incremental summarization, de-duplication, summary updates, conflict identification and experience candidates; it records what it changed and what it consumed, can be reviewed and reverted, and **never widens permissions**. Experiences are verified before they influence tasks; one success never becomes a general rule.

Deliver:
- Schema (host migrations): disabled state, fact/inference kind, experience entries with status (candidate → verified → retired), a change journal for organization runs (run id, inputs by id+revision, outputs, model/profile used if any, outbound record ids, token/time cost, status), and tombstones so deleted or disabled content is never reintroduced.
- A `DreamService` (name yours) that runs incrementally (only memories changed since the last run), offline rules first (exact/normalized duplicates, explicit key/value changes). Model-assisted steps (summary, semantic conflict, experience candidates) run **only** when the user enabled them with an explicitly chosen model profile; requests go through `OpenAiModelGateway` with `caller: 'dream'` and therefore appear in `outbound_requests`; no implicit remote endpoint.
- Every proposal is a reviewable candidate with its evidence (memory ids + revisions). Accepting applies it; reverting a run restores the prior state exactly. Conflicts are shown with their sources, never auto-resolved.
- The assistant uses only enabled, unexpired, in-scope memories and only **verified** experiences; disabled/deleted ones disappear immediately from assistant context and from retrieval.
- Dream holds no tool approvals and cannot call write/external tools; prove it with a test.
- Mobile/desktop background limits: runs are resumable and idempotent; an interrupted run is marked interrupted, not done.

### D5 Cross-device task coordination

Requirement (sections 2.2 and 10): a task package names task identity, input version, executing device, permission scope and expected result. Importing or receiving never authorizes execution; the receiver authorizes locally. Online scheduling must make execution ownership, status queries and duplicate-execution control explicit so the two ends never both run the same operation.

Deliver, on top of your paired TLS channel (business task execution itself stays in the research module, owned by C; use an injected executor):
- An ownership record per (task id, input revision): offered → accepted-by(device) → running → succeeded/failed/cancelled, with a single owner at a time (lease or equivalent) and an idempotency key so a retried offer or a duplicate delivery never causes a second run.
- A status-query message between paired devices; when the peer is unreachable the state is shown as unreachable/unknown, never as failed or done.
- Results return attached to the task id + revision; a late or duplicate result does not overwrite a newer one.
- Loopback tests: duplicate offer, both sides trying to accept, receiver restart mid-run, sender asking status while offline, late duplicate result.

### D6 Tool-selection evaluation

Requirement (section 7): keep the selection layer replaceable; evaluate a limited set of candidate methods including **Jev and Laya**, keep rule and LLM fallbacks; choosing a tool, generating parameters, authorization and execution stay separate; model confidence never replaces a permission decision; no production decision model is chosen yet.

- **What Jev and Laya are** (sources given by the user; read them yourself before implementing):
  - **Jev** — TypeSafe AI's first "System One Model": unstructured state in, typed probabilistic decisions out, no free-text generation, schema conformance guaranteed. **Hosted API only, early access, account required.** TypeSafe has **not** published a technical report, paper or architecture details, and says it will not publish public-benchmark scores.
  - **Laya** — open-source (Apache-2.0) non-autoregressive "System 1" decision engine: typed `choice` / `score` / `noul` (yes/no) decisions with calibrated confidence in one forward pass, 100+ languages, a router that picks a checkpoint per request, optional abstention via `min_confidence`, embedding shortlists for many labels. Python ≥3.10 (`pip install laya`), checkpoints `convaiinnovations/laya` and `convaiinnovations/laya-multilingual` on Hugging Face, extras `laya[serve]` (HTTP), `laya[mcp]` (MCP server), `laya[onnx]` (ONNX Runtime). Source: https://github.com/NandhaKishorM/laya. Its README lists known weaknesses (e.g. `noul` label bias on the English checkpoint, `score` being weakest) — check them against tool selection.
- How to fit them, without changing the authorization model:
  - Map selection to one `choice` decision over the available tool ids plus `"none"`; below a calibrated threshold the strategy abstains (returns no candidate). Parameter generation, host approval and execution stay where they are. A probability is never an authorization.
  - **Laya** for evaluation: run it locally on the desktop (`laya.serve` on loopback, or its MCP server through our `McpAdapter`); Python is not available on Android, so record what on-device use would take (ONNX export via our existing `flutter_onnxruntime`, tokenizer, model size, latency on this Mac's CPU) as a finding, not as a commitment.
  - **Jev: evidence review first, measurement later (user decision).** Do not call the Jev API in this phase. Produce `docs/implementation/jev-evidence-review-<date>.md` from these sources, weighted in this order:
    1. Official primary sources: launch post https://typesafe.ai/blog/introducing-system-one-models-and-jev, product docs https://docs.typesafe.ai/ (state, Choice/Score/Noul, atomic questions, limits, pricing, context size, languages, data handling/retention), and the CEO's own statements (e.g. Hacker News) — treat as vendor claims.
    2. Independent, pre-registered evaluations that publish raw data: https://github.com/priorbench/jev, https://github.com/ejs-5/jev-benchmark, https://github.com/ickma2311/jev-baselines-eval, latency in https://github.com/AbdelStark/jev-benchmarks. Read their methods, not only their headlines; note conflicts between them (e.g. accuracy on routing vs. subtle judgment, measured speedup vs. vendor claims, calibration error, sensitivity to criteria wording).
    3. Secondary summaries (DataCamp, DigitalOcean, MarkTechPost, flaviocopes, etc.) only as leads to primary/independent sources; analyses that guess at undisclosed internals (e.g. RLCD "deep research" posts) are labelled speculation.
    For every claim record: source, evidence type (vendor claim / independent measured / secondary / speculation), reproducibility (raw data? pre-registered?), and relevance to Muyon's tool selection — routing/classification over our tool ids, Chinese and mixed Chinese–English prompts, calibration and abstention, behaviour when tool descriptions are wrong or ambiguous, latency from China, cost, and that prompts plus tool lists would leave the device to a US-hosted service. End with a recommendation: whether a measured trial is worth requesting early access for, and exactly what that trial would test. Measurement happens only if the user then provides an early-access key; it would use only the checked-in synthetic task set, store the credential in the system secure store, and record every request in `outbound_requests` (`caller: 'selection.jev'`).
  - Do not add Python, PyTorch or Laya to the Flutter app's dependencies for this task; the evaluation harness may call them as external local services.
- Fixed task set (checked in, redistributable) over the real registered tools: prompts with the expected tool or "no tool", including ambiguous and adversarial prompts (e.g. text that asks the assistant to approve itself or pick a write tool).
- Metrics per strategy: top-1 / top-k selection accuracy, false selection of write/external tools, abstention quality, latency and cost. Baselines: the current `RuleAndModelToolSelection` offline rule, and the LLM selector (only when a real model endpoint is configured; otherwise "not measured").
- One-command re-run; report in `docs/implementation/tool-selection-eval-<date>.md`. The evaluation recommends; it never switches the production strategy by itself.

## Rules

- TDD; never weaken existing assertions. Do not read, edit or commit `.env`; no secrets in code, tests or logs.
- No new dependency without a written reason.
- Report format as before: commits; test counts per package; evidence class per item (doc / automated test / build / real model / device; unverified stays "unverified"); changes outside owned files (including each host migration); contract requests; requests to B/C; known gaps and risks.

---

# 追加：第 1 阶段审查意见（给 Sonnet、Codex）

---8<--- 追加 · B（Sonnet）· 审查意见 ---

Your branch `feat/b-ui` (B1, B2, B3, G1-B; 7 commits up to `2c310f5`) was reviewed. Strong work: `muyon_ui` with a token-parity test, the data & storage page (catalog, unavailable modules, projection errors), an honest backup → verify → close → restore → reopen flow, the reader's separate page-jump and text-highlight outcomes, G1-B, and a prototype WebView that denies new windows and permissions, runs incognito without cache, and checks every top-level navigation.

Sync first: `git fetch origin && git merge origin/develop` (develop is at `ce928c2` or later). Before every push run `scripts/verify.sh` and make sure it leaves the working tree clean.

Two items must be fixed before B3 can be merged:

**B-R1 — Wire the prototype module into the app.** Today `packages/prototype_module` is not a dependency of `apps/muyon` and is not in `ModuleRegistry`, so users cannot reach it. Add the dependency, register `PrototypeModule()` alongside `ResearchModule()` in `bootstrap.dart`, activate it through the host the same way research is (`storage.open('prototype', module.schema)`, `module_registry` status, `projections.watch('prototype', connection)`, failures recorded instead of thrown), and give it an entry in the shell navigation. Keep the `bootstrap.dart` change minimal and list it in your report. Add a widget test that opens the prototype entry from the shell and a host test that a broken prototype database disables only that module.

**B-R2 — Restrict sub-resource loads, not only navigations.** `shouldOverrideUrlLoading` sees top-level navigations only; `fetch`/XHR, images, scripts, styles and frames loaded by the page can still reach any host, which does not meet "限制资源访问" and could combine with bridge channels to send data out. Block every request outside the spec's allowed roots on each target platform (Android, macOS, Windows):
- inject a strict Content-Security-Policy at document start (e.g. a `UserScript` adding a `<meta http-equiv="Content-Security-Policy">` that only allows the prototype root, with `connect-src` limited to it and no remote origins), and
- use the plugin's request interception where the platform supports it (e.g. `useShouldInterceptRequest`/`shouldInterceptRequest` on Android, content blockers on Apple platforms; check what `flutter_inappwebview` 6.1.5 offers for WebView2 on Windows).
Document per platform which layer enforces the rule and what could only be verified on a real device (mark it "unverified"). Unit-test the policy generator and the guard's decision for sub-resource URLs (remote `https`, `data:`, `blob:`, `..`, other `file` paths).

Also list in your report the two small edits outside your ownership (`research_module.dart`, `devices_page.dart`).

---8<--- 追加 · C（Codex）· 审查意见 ---

Your three inquiry commits were reviewed from your local branch: `81078bd` (SQL triggers record supplier/inquiry/quotation/project/project_item changes in the change log, including raw exchange/merge writes, with a backfill on upgrade — good design), `4a38562` (hosted mode requires host-managed stores; the ontology WebView cache moves under the module directory; hosted wording no longer presents the inquiry snapshot as a full backup), `091c79c` (G4/G5).

**C-R0 — Your push did not reach GitHub.** `origin/feat/c-modules` is still `3bff397` (W0); your local branch is 23 commits ahead (`0b7ce95`). Run `git push origin feat/c-modules`, then confirm with `git ls-remote origin refs/heads/feat/c-modules` that the hash equals `git rev-parse HEAD`. Report the hash.

**C-R1 — One hosted flag, not two.** `AppState` now has both `isHosted => !_ownsJobs` (from `4a38562`) and `_isHosted` (from `091c79c`). Make `isHosted` return `_isHosted`, derive nothing else from `_ownsJobs` for hosting decisions, and add a test that a hosted state with host-owned jobs reports hosted.

Notes:
- Suppliers have no project; A changed the projection so project-less objects are now catalogued under `ProjectionService.globalProject` (`''`). No change needed on your side.
- Commit the in-progress research work (C2 change log, `ResearchSession.objectPage`, G1-C standalone-only LAN) as small commits with a short body each, run `scripts/verify.sh`, push, then continue with C3 (citation anchors), C4 (research package round trip), G2 and G3.
- Before every push: `scripts/verify.sh` green and a clean working tree.

---

# 追加：D4–D6 合入后的遗留（给 Grok）

---8<--- 追加 · D（Grok）· D4–D6 遗留 ---

Your R1–R4 and D4–D6 work was reviewed and merged into `develop` at `df76e83` (full `scripts/verify.sh` green: supplier_core 478 + 3 skipped, host 151 + 1 conditional skip; tests no longer rewrite tracked files). The Jev evidence review is excellent — its stop conditions are exactly what we need. Your ledger edits were accurate and appropriately conservative.

Sync first: `git fetch origin && git merge --ff-only origin/develop`. Keep working on `feat/d-transfer`; push only there; A merges. The machine is shared and often heavily loaded: never run Laya, a build and `flutter test` at the same time; cap Laya CPU threads (e.g. `LAYA_THREADS=4`).

Three follow-ups:

**D-R5 — Wire cross-device task coordination into the app.** Your ledger says `TaskCoordinator` is not wired into startup, so users cannot use it yet. Create it in host startup next to `TransferService` (minimal `bootstrap.dart` change, listed in your report), route incoming offers/status queries/results from the paired transport to it, and show per-task ownership and state (offered / accepted-by / running / done / unreachable) on the devices page you own. Receiving an offer must still never execute anything: execution only after local authorization through an injected executor (research execution itself remains C's). Add a host-level test: two hosts over loopback, one offer, both sides try to accept, exactly one runs; the sender sees "unreachable" when the peer is closed, never "failed" or "done".

**D-R6 — Actually measure Laya on this Mac.** The kickoff asked for a local run; the report says "not installed". Do it now, outside the Flutter app:
- Create a Python ≥3.10 virtual environment **outside the repository** (e.g. under `~/.cache/muyon-eval/`), `pip install "laya[serve]"` (or `laya[mcp]` and reach it through our `McpAdapter`), and run it on loopback only. Never commit the environment, checkpoints or downloaded files; never add Python, PyTorch or Laya to Flutter dependencies.
- Evaluate tool selection as one `choice` over the available tool ids plus `"none"`, with abstention below a threshold you calibrate on part of the task set and test on the rest. Record the exact package version, checkpoint names and revisions, thread count and CPU latency (p50/p95) on this machine.
- Check the README's stated weaknesses that matter here (label bias, behaviour on Chinese and mixed Chinese–English prompts, many-label shortlisting).
- Record what on-device use would take: ONNX export size, whether our existing `flutter_onnxruntime` can run it, the tokenizer it needs, and CPU latency of the ONNX model on this Mac. Findings only, no app integration.
- Only the checked-in synthetic task set is sent to Laya. If installation or the model download fails, report the exact error and keep "not measured".

**D-R7 — A task set that can tell strategies apart.** 11 prompts over 20 of the registered tools are too few. Grow the checked-in, redistributable task set to at least 100 labelled prompts covering every tool actually registered at startup (knowledge, embedding, OCR, transfer, research and all inquiry read/compute tools), with explicit "none" cases, Chinese, mixed Chinese–English, paraphrases, ambiguous requests, wrong/misleading tool descriptions, and adversarial prompts (asking the assistant to approve itself or switch to a write/external tool). Report metrics per category, not only totals, plus calibration (accuracy vs. confidence buckets) for any probabilistic strategy. Re-run the offline rule, Laya (D-R6), and the LLM selector only if a real endpoint is configured; Jev stays "evidence review only" until the user provides a key. Regenerate `docs/implementation/tool-selection-eval-<date>.md` with `MUYON_WRITE_EVAL_REPORT=1`; ordinary test runs must not rewrite it.

Also list the public API B needs to build the memory / experience / Dream review UI (method names, states, what "revert run" restores), so A can hand it to B.

Report in the same final-report format: commits; test counts per package; evidence class per item (doc / automated test / build / real model / device; unverified stays "unverified"); changes outside owned files; new dependencies (none expected in the app); contract requests; known gaps and risks.

---

# 新角色 E：opencode（DeepSeek v4.1 flash）启动提示词

分工依据：速度快、成本低，适合范围明确、接口现成、可用测试验收的任务；不承担安全协议、架构取舍和长链推理。

---8<--- E · opencode · 启动 ---

你是 Muyon 项目的 **E 角色：支援开发**。集成者 A（另一个 Claude Opus 会话）负责契约、主库结构、审查与合并。只做下面的任务，只改你拥有的文件。

## 环境

- 仓库 `github.com/mightyoung/Muyon`。你的工作目录 `/Users/muyi/Downloads/dev/muyon-worktrees/e-support`，分支 `feat/e-support`。**不要**进入 `/Users/muyi/Downloads/dev/muspace` 或其他 Agent 的目录。
- 开工：`git fetch origin && git merge --ff-only origin/develop`，然后在仓库根目录 `flutter pub get`。
- 每次推送前必须运行 `scripts/verify.sh`，退出码为 0，且运行后 `git status` 干净。推送后执行 `git ls-remote origin refs/heads/feat/e-support`，确认远端哈希等于 `git rev-parse HEAD`，并在报告里写出这个哈希（之前有 Agent 以为推送成功但实际没有）。
- 机器多人共用、负载经常很高：同一时间只跑一个 `flutter test` 或构建；中断后清理残留的 `flutter_tester` 进程。
- 只做自动测试与静态分析，不声称实机通过。

## 必读

1. `docs/superpowers/plans/2026-10-04-muyon-parallel-dev-plan.md`（第 2、4 节协作规则）
2. `docs/design/DESIGN.md`（所有页面遵循 Folio 风格；只用 `packages/muyon_ui` 的 token，不硬编码颜色和字号）
3. `apps/muyon/lib/platform/outbound_ledger.dart`、`tool_registry.dart`、`mcp_adapter.dart`
4. `apps/muyon/lib/services/models/secret_store.dart`
5. `apps/muyon/lib/screens/data_storage_page.dart`（参考它的结构与测试写法）

## 你拥有的文件

- 新建：`apps/muyon/lib/screens/data_flow_page.dart`、`apps/muyon/lib/screens/mcp_servers_page.dart`，以及对应的 `apps/muyon/test/*` 新测试文件。
- 允许的最小改动（每处都要在报告里列出）：在 `data_storage_page.dart` 加入口（一两行）；在 `apps/muyon/lib/app/bootstrap.dart` 加最少的接线。
- 不属于你：`packages/muyon_module_api`、`apps/muyon/lib/platform/**`（只读调用，不改）、其他页面、各业务模块包。需要改这些地方时写进报告的"请求"一节，由 A 处理。

## 任务

### E1 "数据去向"页面
用户要能看清"数据实际发到了哪里、工具做了什么"。
- 列出 `host.outbound.recent()`：时间、调用方（assistant / research.qa / embedding / inquiry / dream …）、端点、本机还是远程、是否经云代理、模型、载荷大小与条数、状态（sending / succeeded / failed / cancelled / timeout / interrupted）、错误说明。**不显示载荷内容**（记录里本来就没有）。
- 列出工具调用：`host.tools.history()` 的状态与摘要；需要批准和目的地信息时只读查询主库 `tool_approvals` 表（`destination`、`issued_at`、`expires_at`、`state`）。
- 状态用文字加图标区分，不只靠颜色；`interrupted` 必须写明"结果未知，重试前请先核实"。
- 支持按调用方和状态筛选；空状态与读取失败状态都要有明确文案。
- 测试：用真实的临时宿主（参考 `acceptance_failure_matrix_test.dart`）插入各种状态的记录，断言显示正确；320 与 1280 宽度、200% 字号下不溢出。

### E2 MCP 服务器配置页
- 新增、编辑、删除服务器：`id`、`endpoint`、可选的令牌。配置（不含令牌）以 JSON 存到 `host.workspaces.setSetting('mcpServers', ...)`；令牌只通过 `MethodChannelSecretStore.write/remove` 写入系统安全存储，引用名用 `mcp-<id>`。
- 输入校验沿用 `McpServerConfig` 的规则（https 或本机 http、简单 id），错误就地提示。
- "连接"按钮调用 `McpAdapter.connect(host.tools, config, secrets: ...)`，显示已注册的工具与跳过原因。**只在用户点击时连接，启动时不自动联网。**
- 删除服务器时：删除配置与令牌，并用 `host.tools.setAvailability(toolId, available: false, reason: '服务器已移除')` 停用它注册过的工具（注册表没有注销接口，不要去改注册表）。
- 页面写明：调用这些工具会把参数发给该服务器，每次调用都要你确认。
- 测试：用本地假 MCP 服务器（可参考 `test/mcp_adapter_test.dart` 里的 `_FakeMcp`）覆盖：保存与重新读取配置、令牌不出现在设置 JSON 里、连接后工具出现、删除后工具变为不可用；安全存储在测试中用注入的替身。

### E3 平台层测试覆盖率
- 运行 `flutter test --coverage`（在 `apps/muyon`），统计 `lib/platform/**`、`lib/workspace/**`、`lib/services/models/**` 各文件的行覆盖率，写入 `docs/implementation/coverage-<日期>.md`（附可重复运行的命令）。
- 对低于 80% 的文件补测试，**只加测试，不改产品代码**。发现疑似缺陷时不要顺手修，写进报告，由 A 判断。
- 不得削弱或删除已有断言。

## 规则

- 先写测试，再实现。所改包 `flutter analyze` 无问题。
- 不读、不改、不提交 `.env`；代码、测试、日志里不出现密钥。
- 不新增依赖；确实需要时写明理由，等 A 同意。
- 小提交（每个不超过约 400 行），Conventional Commits 格式，提交说明写一两句原因。只推送到 `feat/e-support`，**不要合并到 develop**。

## 交付报告

1. 提交列表（哈希 + 一句话）和远端核对过的哈希
2. 各包测试数与 analyze 结果
3. 每项的证据类别（文档 / 自动测试 / 构建 / 真实模型 / 实机），没验证的写"未验证"
4. 拥有范围外的改动（逐条）
5. 覆盖率数字（前后对比）与发现的疑似缺陷
6. 已知缺口与风险

---

# 追加：Laya 专门化（给 Grok）

---8<--- 追加 · D（Grok）· D-R8 Laya 专门化 ---

**Priority:** first finish, verify and push your current D-R5 / D-R6 / D-R7 work. Start this only afterwards.

Your D-R6 measurement (held-out 93 tasks: top-1 46/93, false write/external 0, adversarial and ambiguous all abstained, Chinese 5/18, mixed 6/18, paraphrase 1/19, ≥0.9-confidence answers 28/29 correct, CPU p50 ≈ 440 ms) shows Laya is safe but abstains on most Chinese, mixed and paraphrased requests. Its README says it is "a fast base to specialise, not a zero-shot decision engine" and ships a fine-tuning pipeline. The user has decided to try specialisation, **with training on Kaggle**. Work in three stages; each stage ends with a report and stops if its gate fails.

Where things live: training and evaluation scripts and the **synthetic** training data under `scripts/laya/` (committed, redistributable, no user data). Python environments, checkpoints, Kaggle outputs and downloaded weights stay **outside the repository** (e.g. `~/.cache/muyon-eval/`), never committed. Do not add Python, PyTorch or Laya to the Flutter app.

### Stage 1 — Better questions, no training

Before any training, fix how the question is asked; this may close much of the gap:
1. Options carry the **Chinese tool description** (plus a short English gloss), not the raw tool id; keep ids only as opaque keys. The README says choice labels are rendered verbatim and boolean-like labels bias answers.
2. Raise `head_max_len` for the multilingual checkpoint as needed, and add an **embedding shortlist** (`predict_shortlist`) so the option budget stays above a sane token count per option as the tool list grows (MCP tools make it dynamic).
3. **Per-category calibration** (temperature fitting or per-category thresholds) instead of one global 0.95; optionally a two-step question ("does this need a tool?" `noul`, then `choice` over the shortlist).
4. Add a **negation set** (e.g. "不要删除…", "先别发出去", "don't cancel…"); the README documents a case where negated requests chose the destructive option at 0.9998.

Gate 1: on the held-out split, false selection of write/external tools stays **0**, including adversarial and negation items. Report per-category top-1, abstention, calibration (accuracy per confidence bucket) and latency against your D-R6 baseline.

### Stage 2 — Fine-tune on Kaggle

- **Training data:** generate ≥1,000 labelled synthetic requests yourself (no external model needed) from the registered tools' descriptions: Chinese, mixed Chinese–English, paraphrases, "none", ambiguous, negation and adversarial cases. Labels are description-conditioned (the model chooses among the option texts it is shown, with random subsets and random order of tools per example), so it learns to read descriptions rather than memorise ids.
- **No leakage:** the existing 140-task evaluation set is never used for training. Check exact and near-duplicate overlap (normalised text n-gram similarity) between training and evaluation sets and report it. Hold out a few **tools** entirely from training to measure generalisation to unseen tools.
- **Kaggle:** use the official `notebooks/laya_finetune_typed_decisions_2xT4_kaggle.ipynb` flow (RLCD training, calibration temperatures, evaluation). Kaggle credentials: the user put a Kaggle API token (new `KGAT_…` format) in `/Users/muyi/Downloads/dev/muspace/.env` under the key `Kaggle-apikey` (the file also holds other secrets; it is git-ignored). The key name contains `-`, so do **not** `source` the file. Read only that one key with a small script and pass it to the Kaggle CLI/API **as an environment variable of that subprocess only** (check the installed `kaggle` package's docs for the variable it expects for `KGAT_` tokens, e.g. `KAGGLE_API_TOKEN`). Never print it, log it, write it to another file, put it in a notebook, or commit it; never read the other keys in that file. Upload only the synthetic data, as a **private** Kaggle dataset. **Do not push** the resulting checkpoint to the Hugging Face Hub (disable the notebook's push step, or push only to a private repo if the user explicitly provides a token for that); download the weights to `~/.cache/muyon-eval/models/` and record their SHA-256.
- Record: base checkpoint and revision, Laya version, notebook version, hyperparameters, seed, GPU type and training time, dataset size per category.

Gate 2 (proposed targets — **the user must confirm or change them**; report against them either way): false write/external **0** on held-out, adversarial and negation; held-out Chinese, mixed and paraphrase top-1 each ≥ 0.70; overall held-out top-1 ≥ 0.80; unseen-tool top-1 ≥ 0.60; ECE ≤ 0.10 after calibration; CPU p50 on this Mac no worse than 1.5× the D-R6 baseline.

### Stage 3 — Feasibility only, no app integration

- Export the fine-tuned model to ONNX using the repository's export script from the Laya **source tree** (the PyPI wheel lacks `scripts/export_onnx.py`), with the README's per-tensor quantisation default; record file size, whether our `flutter_onnxruntime` 1.8.5 can load it, the tokenizer needed, and CPU latency on this Mac, and confirm the ONNX outputs agree with the PyTorch model on the evaluation set.
- Write `docs/implementation/laya-specialisation-<date>.md`: what changed per stage, all numbers, gate results, costs, risks (tool-list drift, negation, distribution shift from synthetic to real requests), and a recommendation. Integration into the app is a separate decision by the user.

Rules as before: evidence classes (doc / automated test / build / real model / device; unverified stays "unverified"); no secrets anywhere; one heavy job at a time on this shared machine; push only to `feat/d-transfer`; A merges.

**What you need from the user (put at the top of your report when you reach Stage 2):** the Kaggle account must be phone-verified (required for GPU sessions). If the token in `.env` is rejected or lacks permission, report the exact error message (without the token) and stop; do not ask for the token in chat.

---

# 追加：一对一文字聊天后端（B 草案经 A 审定，给 Grok；附给 Sonnet 的界面调整）

B's draft is `docs/implementation/chat-interface-draft.md` on `feat/b-ui` (`91deaba`). A accepted it with the changes below; this section is the binding spec.

---8<--- 追加 · D（Grok）· D-R9 一对一文字聊天后端 ---

**Priority:** after your current D-R5 / D-R6 / D-R7 work is committed, verified and pushed; before D-R8 Stage 2 (Kaggle training). Commit what you already have in small commits first — the machine rebooted once today and uncommitted work is at risk.

Requirement: online one-to-one text chat and attachments between the user's own paired devices; reachability, send progress, receipt confirmation and results visible; delivery, durable receipt, business import, read and human acceptance recorded separately; both peers online, authenticated, reachable; no promise of relay or NAT traversal.

Today the `message` field of a transfer package is dropped at verification/import and sent text is not recorded, so the UI has no history and no delivery state. Build the backend so B can build the UI.

**Storage.** A new migration in `KnowledgeService.schema` (the database `TransferService` already uses, next to `transfer_items`), so message state and transfer receipts commit through the same write queue. Not the host main database. Table `chat_messages`:
- `peer_fingerprint`, `message_id` (sender-generated UUID) — **unique together**; dedupe on the pair, never on `message_id` alone.
- `direction` `out`/`in`; `body` ≤ 16,000 characters (same limit as the package `message`); `created_at` (sender clock, display only); local `sent_at` / `received_at` for ordering.
- `send_state` (out only): `queued` → `sent` (bytes written) → `delivered` (peer confirmed it durably stored), or `failed` + `error`.
- `read_at` (local only). `acceptance` (in only): `none` / `accepted` / `rejected` — see below.

**Semantics (binding):**
1. Text travels only over the existing paired TLS channel to a paired, online, unrevoked peer, through the same checks as `send`. Offline peer → fail immediately with "no relay", no queueing. Revoked pairing → history stays readable, sending is refused.
2. `delivered` only after the receiver's durable-store acknowledgement on the authenticated connection. If the connection drops or times out after `sent`, the state stays `sent` (outcome unknown): **never auto-retry, never mark failed**. `retry(messageId)` is explicit, allowed for `failed` and for `sent` older than a timeout; the receiver's dedupe makes it safe.
3. **Inbound text is shown in the conversation immediately** as unread (these are the user's own paired devices). `acceptance` is a separate, optional state used only when the user turns a message into business data (e.g. attaches it to a project); `accept`/`reject` never import or execute anything. Read and acceptance stay independent.
4. Chat text is untrusted data: it never grants tool permission (`grantsExecution == false`), is never auto-added to assistant context, and is reachable by the assistant only through a registered read tool with an explicit scope (not part of this task).
5. No read receipts are sent to the peer; `read_at` is local.
6. The `message` of a transfer package is also written to `chat_messages` as an inbound message linked to that package; the package's import/acceptance stays independent of the message.
7. Local delete (`delete`, `deleteThread`) removes local records only; the peer is unaffected.
8. Receiving a message uses the existing `onPendingReceived` notification path.

**API on `TransferService`** (names may be adjusted; document final ones): `sendText(peer, body)`, `threads()` (per peer: last message, unread count, online, paired, peer name), `messages(peerFingerprint)`, `markRead(peerFingerprint)`, `accept(messageId)`, `reject(messageId)`, `retry(messageId)`, `delete(messageId)`, `deleteThread(peerFingerprint)`, and a change notification (`Stream` or `ChangeNotifier`).

**Tests (loopback, two hosts):** send → `sent` → `delivered` → shown unread on the receiver; duplicate delivery of the same (peer, id) keeps one row; drop after `sent` stays `sent` with no auto-retry; explicit retry is deduplicated; offline peer fails immediately; revoked pairing refuses to send but keeps history; accept/reject change only `acceptance`; package message appears in chat without changing package import state; nothing reaches the tool registry or assistant context.

Report the final API (names, states, errors) in `docs/implementation/chat-interface-draft.md`'s follow-up section or a new `chat-backend.md`, so B can build against it.

---8<--- 追加 · B（Sonnet）· 聊天界面的调整 ---

Your chat backend draft was accepted with changes; D is implementing it. What changes for the UI:
- Inbound text appears in the conversation **immediately as unread**; there is no per-message "pending acceptance" gate. "Accept / reject" becomes an optional action used when turning a message into business data (e.g. attaching to a project), and is shown as its own state, separate from read.
- Storage is in the transfer service's database, not the host main database (no effect on your UI code).
- Dedupe is per (peer, message id); no read receipts go to the peer.
- `sent` with an unknown outcome is a real, persistent state: show it as "已发出，对方是否收到未知", and only offer retry with the warning you proposed.
Wait for D's final API document before wiring; you can build the screens now against a fake.

---

# 追加：E 角色第二批任务（给 opencode）

---8<--- 追加 · E（opencode）· E4–E5 ---

你的 E1–E3 已审查并合入 `develop`（`c547fcf`）：数据去向页、MCP 服务器页、平台层覆盖率 83.9% → 90.1%，只加测试不改产品代码，报告也写得准确。下面是第二批任务。

开工：`git fetch origin && git merge --ff-only origin/develop`。推送前 `scripts/verify.sh` 退出码为 0、运行后 `git status` 干净；推送后用 `git ls-remote origin refs/heads/feat/e-support` 核对远端哈希等于 `git rev-parse HEAD`，在报告里写出哈希。规则同上一份提示词（不改 `.env`、不加依赖、小提交、只推送到 `feat/e-support`、不合并到 develop）。机器负载很高，同一时间只跑一个测试或构建。

### E4 消除验证脚本里唯一的"已知失败"

`scripts/verify.sh` 一直放行询价模块 `packages/inquiry_module/test/screenshot_test.dart` 的 `desktop settings` 截图失败。按 `packages/inquiry_module/MIGRATION_VALIDATION.md` 的记录，这是当前 Flutter SDK 渲染变化造成的：与冻结的基准图相差 158 个像素（0.02%），位置在一个下拉箭头上，原始未改动的代码也能复现。A 已决定更新这张基准图，因为长期放行会掩盖这个测试以后真正的回归。

步骤（必须按顺序，任何一步不符合就停下并报告，不要更新）：
1. 在 `apps/muyon` 下运行该测试，取得实际渲染图和差异图（`test/failures/` 下，已被 git 忽略），核对差异仍然只在那个下拉箭头附近，像素数不超过约 0.05%。把你看到的差异位置和像素数写进报告。
2. 只更新这一张基准图：`flutter test --update-goldens --plain-name 'desktop settings' ../../packages/inquiry_module/test/screenshot_test.dart`，其他基准图一张都不能变（用 `git status` 确认只有这一个 PNG 改动）。
3. 记录旧图和新图的 SHA-256，追加到 `MIGRATION_VALIDATION.md` 的那一节，写明日期、Flutter 版本和原因；不要删掉原来的记录。
4. 从 `scripts/verify.sh` 的 `KNOWN_FAILURES` 里移除这一条（保留数组本身，留空），并确认 `verify.sh` 在没有任何失败时仍然输出 ok、退出码 0。

所有权例外（A 授权）：本任务可以改这一张基准图、`MIGRATION_VALIDATION.md` 和 `scripts/verify.sh` 的那一行，不改询价模块的任何代码和其他测试。

### E5 助手层测试覆盖率

范围：`apps/muyon/lib/assistant/` 下的 `action_gate.dart`、`execution_store.dart`、`personal_agent.dart`、`qa_service.dart`、`tool_selection.dart`。**不碰** `assistant/dream/**` 和 `assistant/selection_eval/**`（Grok 正在改）。
- 用与 E3 相同的方法统计行覆盖率，追加到 `docs/implementation/coverage-<日期>.md`（新日期就新建文件，命令可复用）。
- 低于 80% 的文件补测试，**只加测试，不改产品代码**。优先覆盖这些行为：取消与中断后的状态、模型请求被拒绝或失败时不保存答案、引用不在冻结证据内时拒绝、范围变化后拒绝发送、工具选择只给候选不授权。
- 发现疑似缺陷不要顺手修，写进报告由 A 判断。不得削弱或删除已有断言。

## 交付报告

1. 提交列表和远端核对过的哈希
2. E4：差异位置与像素数、新旧图 SHA-256、`verify.sh` 运行结果
3. E5：覆盖率前后对比、新增测试数、疑似缺陷
4. 拥有范围外的改动（逐条）
5. 各项证据类别（文档 / 自动测试 / 构建 / 真实模型 / 实机），未验证的写"未验证"
