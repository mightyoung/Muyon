# REG-4c 实施与验证回报

独立分支：`task/reg-4c-general-writes`；基线 develop：`7773b7d96bc99f173b57a723d61526fba0df49ff`。草稿 PR：[#31](https://github.com/mightyoung/Muyon/pull/31)。开始前已更新全部远端分支并检查同任务分支/开放 PR，没有重复 active 实现。父任务独占最终审查及合入 develop。

## 工具、范围与回执

4 个宿主工具均为 `ToolEffect.write`、仅 `selectedObjects`、数据模块仅 inquiry；不新增自动批准通道。审批仍由宿主确认卡/原授权策略执行，模型传 operation_id 不构成批准。

| 工具 | 必填输入 |
| --- | --- |
| `inquiry.create_record` | `operation_id`、`type`、`values` |
| `inquiry.update_record` | `operation_id`、`type`、`id`、`expected_version`、`values` |
| `inquiry.delete_record` | `operation_id`、`type`、`id`、`expected_version`、`referencing_records` |
| `inquiry.restore_record` | `operation_id`、`type`、`id`、`expected_version` |

`operation_id` 是稳定 UUID v4；同一业务重试沿用它。`type` 只允许 supplier、contact、product、project、project_item、inquiry、quotation。字段模式取实际本体；宿主不支持 oneOf/条件模式，因此发布字段联合，再在批准前及事务内检查所选类型的精确白名单。未知字段、受保护字段 merged_into/attachment_ids/source_attachment_ids/capture_mode 均拒绝；values 只包含修改字段，合并完整载荷后 `validatePayload`，再由 `Store.save` 校验。

quotation 仅开放 quoted_on、lead_time_days、warranty_months、valid_until、notes；价格、币种、税、报价身份及定标字段不可写。通用 create 不能补造必填价格，因此完整报价创建仍用 `inquiry.record_quote`。

执行事务内复核选定对象身份、revision、digest、工作区绑定和 expected_version；新引用必须在人工选定对象中。新建全局目录记录需已选全局询价对象；新项目返回自身 project ref；项目数据不得越出选定项目。业务操作的参数及逻辑范围哈希、结果回执和领域变更同事务写入；跨 invocation 重试不重复生效，换参数/范围拒绝。Store 原 changelog 及宿主审计回执保留。

删除预览必填所有活跃引用对象的 type/id/version；执行时重算 `referencesTo` 加同类型引用，预览漏项/变动或存在引用即拒绝。恢复须明确选定带 revision 的删除回执；询价专属旧桥接器将显式选定交由 v2 会话解析，普通枚举和页面仍排除删除对象。恢复的出向引用必须活跃。

## 覆盖清单与 Q3

`apps/muyon/lib/app/adapters/inquiry/coverage.dart` 登记查询、原 4 个具名写工具、新 4 个通用写工具及人工上下文导入。product_param、spec_records（spec_*）、merge_duplicates、award、refresh_prices 均为 `deferred(REG-4)`，逐项说明派生 ID/级联/快照/批量计划所需专用工具；不虚报已开放能力。

宿主 Folio 隐藏桌面侧栏、移动导航、Ctrl/⌘ 数字快捷键和命令面板的问数据入口；强制初始 ask 或旧任务恢复不能进入对话。宿主设置隐藏助手权限和联网开关，遗留 AskPage 的联网自动批准也排除 hosted。历史 bypass 存储不再提供宿主绕过入口；standalone 保持原行为；智能材料导入保留。

## 两项 Store 实测

使用测试临时 Store，无真实业务库写入：

1. 原 unit_cost 为 0、定标写入 18 后，`withdrawAward` 清除定标字段，但预算 unit_cost 仍为 18，quotation_id 仍指向该报价；**不会恢复定标前旧值**。据此保持定标/撤回为 deferred，未改领域行为。
2. `Store.delete` **允许删除仍被 quotation 引用的 contact**，报价引用保留，会产生悬空活跃引用；`referencesTo` 可识别该引用。新 delete_record 拒绝此删除，且验证预览与选定范围，不改变原人工 Store 删除行为。

## 验证与例外

有效行为 RED：提交 `89034827719ef25dabe991f01f70297407f20ebf`、[专用 run 38028474611](https://github.com/mightyoung/Muyon/actions/runs/38028474611)，4 通过/14 失败；失败为缺少新工具和宿主仍显示助手等行为断言，无 loader 失败。更早 a053b8a 的测试自身类型错误不计有效 RED。

环境例外：当前执行环境没有 Flutter/Dart SDK；官方及镜像 SDK 下载被代理 403 阻断，因此不能在本地运行 Flutter 后再推送。采用仓库既有 GitHub Actions 的 Flutter 3.47.5、专属行为/变异工作流，明确记录云端 RED/候选校验例外。格式化仅在临时副本输出投影，再显式应用到源码；工作流测试源码 checkout，不偷偷格式化待测树。

本地 Python 门禁回归 9/9、doctor 场景 23/23、验证脚本 py_compile 及 git diff --check 通过。Flutter 最终结果及 exact-head run 链接在 PR #31 的验证记录中提供；未完成的 run 不视为通过。五项变异在隔离仓库副本逐项移除版本检查、放开保护字段、放开报价价格、恢复宿主助手入口、降格写效应绕过批准；须对应行为断言失败且源码恢复后再次 GREEN。

499e1f5 候选的全量验证发现字段模式重复携带本体说明文字，导致原 `assistant_production_model_protocol_test` 的 12,000-token 窗口在历史压缩后仍超限；另有新文件格式化后触发的花括号 lint。精简新工具说明，字段/类型/枚举保留；重复的字段字符串 2000、数组 500、数组项 200 长度约束移到同样批准前执行的 preflight，新增拒绝测试，执行事务内也再次检查。补花括号；没有调整共享模型预算或放宽原测试。专属门禁额外运行该原协议测试，最终结果仍以 PR exact-head 证据为准。

原测试保留：注册目录在原冻结目录外精确增加 4 项并继续比较全部原工具；hosted 旧权限测试收紧为整个控件不存在；standalone 测试不放宽。Linux inquiry 现有 Mac 字体截图跳过按备忘录记录，不能据此宣称 Mac 截图、真机或真实模型验证通过。原始 RED/候选日志只在 `/tmp/reg4c-evidence` 和 Actions artifact，不入仓库。

文件所有权：只涉及询价域、专属适配器/桥接/注册、hosted Folio 入口、专属测试/验证脚本/工作流及本回报；没有修改 F5b 的 shared UI state/surface/module_api 新目录。未修改 main、合 develop、强推、删分支或部署。

## 共享工具目录阻塞：提交给唯一 integrator 的定位

运行源码 head：`01cebb90ff0b4372f65db55f098c68ba9d4f55fc`。该 head 的 [push CI](https://github.com/mightyoung/Muyon/actions/runs/38030502715) 和 [PR CI](https://github.com/mightyoung/Muyon/actions/runs/38030505531) 均已到 failure 终态：analyze 8/8 通过，测试套件 7/8 通过；host `+1505 ~3 -1`、inquiry `+289 ~47`，北极星夹具 `passed=true`。唯一失败为下面的原宿主测试；未删除或放宽任何断言。

失败测试：[assistant_production_model_protocol_test.dart](../../apps/muyon/test/assistant_production_model_protocol_test.dart#L131)，完整名称 `actual host same-endpoint summary uses model mode_auto and preserves taint`，失败断言在第 163–165 行：期望 `PersonalTaskState.succeeded`，实际 `failed`，错误 `context_too_large`。

| 源码候选 | 压缩前估算 token | 压缩后估算 token | 结果 |
| --- | ---: | ---: | --- |
| `499e1f5` | 15,860 | 14,102 | 超过原门禁 |
| `0586002`（去字段重复说明） | 14,021 | 12,263 | 超过原门禁 |
| `01cebb9`（长度约束移至同效 preflight、精简工具说明） | 13,412 | 11,654 | 超过原门禁 |

原夹具能力为 `contextTokens=12000`、`maxOutputTokens=512`；原 `ContextCompactor.hardRatio=0.95`，所以硬门禁是 `floor(12000 × 0.95) − 512 = 10888`。这是原有预算规则，不是本任务新设的阈值。最新超限量为 766 token。日志中的 `tokenSource=estimated`、`strategy=B`、`upTo=4`、`overCount=1`；上表为实际日志摘要，原始日志不入仓库。

关键路径：

1. [agent_task_factory.dart](../../apps/muyon/lib/assistant/agent_task_factory.dart#L42) 的 `chatTask` 构建 available 列表，过滤停用、只读、modelSelectable 和类别，但没有检查注册器持有的 `supportedScopes`；`selectionStrategy.select` 接收该列表，`_nativeToolSpecs` 据 candidateIds 构造冻结模型目录。
2. [tool_registry.dart](../../apps/muyon/lib/platform/tool_registry.dart#L269) 已保存不可变 `supportedScopes`；第 348 行 prepare 会拒绝不匹配的调用，但目录冻结发生在调用前，因而无效范围的模式仍占模型窗口。`RegisteredToolInfo` 不暴露此字段，不能直接写 `t.supportedScopes`。
3. 该夹具是默认 global 会话；4 个新通用写工具只声明 selectedObjects，global 里根本不能执行。它们的模式却进入 nativeTools，扩大了不可通过摘要压缩的固定目录。

选择范围过滤的原因：它让目录与注册器现有执行权限一致，减少本会话不能执行的候选，而不扩大模型声明的窗口、不减少输出保留、不改压缩保留历史或污点规则。继续抹掉字段类型/枚举以适配某个夹具会降低工具输入说明质量，仍不能解决后续模块目录增长；更改预算或增加夹具窗口则会绕开真实门禁。过滤只是发现层约束，prepare/invoke 的范围复核、审批、revision 与回执仍须保留，不能以目录缺席代替执行鉴权。

### 获权实施的精确 diff

两个共享文件已由唯一 integrator 正式划权，限定范围目录过滤及独立回归；F5b 的 shared UI state/surface/module_api 新目录不涉及。以下补丁此前在上述 head 上通过 `git apply --check`；在取得下述有效行为 RED 后已实施。验证过程及最终 exact-head 结果在 PR #31 更新，不预先宣称 GREEN。

```diff
diff --git a/apps/muyon/lib/assistant/agent_task_factory.dart b/apps/muyon/lib/assistant/agent_task_factory.dart
--- a/apps/muyon/lib/assistant/agent_task_factory.dart
+++ b/apps/muyon/lib/assistant/agent_task_factory.dart
@@ -49,5 +49,8 @@
                 ctx.uiPlanning?.enabled == true) &&
             t.available &&
+            ctx.tools.supportsScope(
+              t.descriptor.toolId, conversation.scope.kind,
+            ) &&
             (!readonly || t.descriptor.effect == ToolEffect.read) &&
             t.descriptor.modelSelectable &&
             ctx.tools.permitsCategory(t.descriptor.toolId),
diff --git a/apps/muyon/lib/platform/tool_registry.dart b/apps/muyon/lib/platform/tool_registry.dart
--- a/apps/muyon/lib/platform/tool_registry.dart
+++ b/apps/muyon/lib/platform/tool_registry.dart
@@ -281,3 +281,6 @@
+  bool supportsScope(String toolId, AssistantScopeKind kind) =>
+      _require(toolId).supportedScopes.contains(kind);
+
   Set<String> authorityModules(String toolId) {
     final tool = _require(toolId);
     return Set.unmodifiable(
```

### 当前失败最小复现

在仓库使用现有 Flutter 3.47.5 / Dart 3.13.4，先 `flutter pub get`，再从 `apps/muyon` 运行以下原测试单例；不修改夹具窗口或断言，不启用真实模型：

```sh
flutter test --no-pub --reporter expanded \
  test/assistant_production_model_protocol_test.dart \
  --plain-name 'actual host same-endpoint summary uses model mode_auto and preserves taint'
```

夹具只创建临时宿主目录与 loopback 无凭据模型服务。种子为 8 条交替 user/assistant 历史，每条 `history-$i-` 加 `'abcd' * 600`；模型应答队列是一条摘要和一条答案，模型能力按上述 12,000/512 声明。失败无需询价业务种子、真实业务库、真实模型或 F5b UI。环境代理需按现有 ci.sh 在 pub get 后清除 HTTP(S)/ALL_PROXY 并设置 `NO_PROXY=localhost,127.0.0.1,::1`，否则会引入无关 localhost 通信失败。

最新 [专属 run](https://github.com/mightyoung/Muyon/actions/runs/38030502603) 已在原源码上确认询价行为基线 GREEN，随后运行原协议测试失败；源码没有临时套入过滤补丁。由于协议门禁停止流程，此 head 的五项变异尚未再次执行；不能用 `499e1f5` 上的 5/5 检出替代它。

### 获得所有权后的安全不变量测试设计

拟增加专属回归，原宿主窗口测试原样保留：

| 不变量 | 构造与断言 |
| --- | --- |
| 目录与注册范围一致 | 注册 global-only、workspace-only、selectedObjects-only、支持所有范围的工具；对三类会话分别检查 candidateIds 及 nativeTools，只包含该范围支持的候选，支持所有范围者保留。 |
| 通用询价写入仍可发现 | global 会话的 candidateIds/nativeTools 不含新四工具；选定实际 inquiry 对象的会话须完整包含这四个工具。使用 loopback 原夹具，不引入真实模型。 |
| 过滤不成为执行鉴权 | 从 global 直接构造新工具请求，prepare/invoke 仍因 scope_mismatch 拒绝；选定对象但未批准的写入仍不得变更 Store 或写业务回执；不能仅断言目录缺席。 |
| 既有目录门禁仍有效 | 匹配范围也不得重新暴露停用、modelSelectable=false、类别禁止的工具；只读子会话不包含 write/export/network，保留原断言。 |
| 没有预算或污点绕过 | 原失败单例须成功，并保留两次模型请求、mode_auto 来源、摘要存在、旧历史 requiresConfirmation=true 的全部原断言；能力仍为 12000/512，hardRatio 仍为 0.95。 |
| 冻结任务不改权 | 新任务目录按创建时 scope 冻结；后续模块停用/对象 revision 变化仍由调用端复核拒绝，既有回执与批准绑定不得改变。 |

执行顺序：先记录目录过滤断言的有效 RED，再应用获准的共享补丁；运行目录回归、原协议单例、north_star_inquiry/inquiry_* 原测试；完成新 head 基线 GREEN、五项安全变异各自行为断言失败、恢复源码 GREEN；最后完整 ci.sh、push/PR exact-head CI 跟到终态。失败在授权范围内修复，仍不放宽窗口或删除断言。

### 获权后实际执行记录

唯一 integrator 已正式授权 `agent_task_factory.dart`、`tool_registry.dart`，非作者复审精确提案没有确定阻断。两文件只新增只读范围查询与 chat 候选目录过滤；原 invoke/prepare 鉴权、预算/窗口/压缩参数、旧历史污点及原协议测试断言没有修改。

独立回归为 `apps/muyon/test/inquiry_scope_catalog_test.dart`：三种范围分别检查注册矩阵、candidateIds 与 nativeTools；保留全范围工具，排除停用和 modelSelectable=false 工具；global 无新四写工具但 selectedObjects 必须仍可发现；直接 global 请求仍 `scope_mismatch` 拒绝，未批准的选定写入仍不得修改 Store/业务回执。

有效范围 RED 为 `a2e94be44d655efb210c306b2f98a5133ecb5cd8`、[run 38032601387](https://github.com/mightyoung/Muyon/actions/runs/38032601387)：询价基线 GREEN；新目录回归 1 通过/4 失败，实际 Set 包含额外不匹配范围工具，或 global 目录仍含通用写工具；没有 loader 错误。更早 cc0f067 的夹具 const 构造错误不计有效 RED。原始证据仍仅在 `/tmp/reg4c-evidence/a2e94be-effective-scope-red.log` 和 Actions artifact。

专属门禁现在依次运行询价行为基线、新范围回归、原宿主协议测试；隔离副本执行原五项写入安全变异，再将范围查询强制 true，要求新 global 矩阵断言失败；恢复后再次运行询价基线及范围回归。最终新 head 的完整 CI、五项安全变异和范围变异均需实际结果确认，不能引用前一 head 代替。
