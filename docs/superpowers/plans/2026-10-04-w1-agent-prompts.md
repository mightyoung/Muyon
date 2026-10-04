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
