# 原型模块能力覆盖清单初稿（GROK-2）

日期：2026-10-07 · 任务：[GROK-2](../../tasks/GROK-2.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-2-coverage-drafts`
方法：只读扫描 `packages/prototype_module/lib`；**未**运行 Flutter。Q10：`add_feedback` 开放为 write；选目录导入与删除类 `humanOnly`。

## 1. surfaces 表

| 库路径 | 类或扩展名 | 公开成员数 | 说明 |
|---|---|---|---|
| `package:prototype_module/src/prototype_store.dart` | `PrototypeStore` | 8 | 业务库操作面（页/版本/反馈） |
| `package:prototype_module/src/prototype_module.dart` | `PrototypeRuntime` | 4 | 导入流水线与会话工厂 |
| `package:prototype_module/src/prototype_module.dart` | `PrototypeSession` | 4 | 范围解析与对象页 |
| `package:prototype_module/src/prototype_module.dart` | `PrototypeModule` | 4 | 模块契约；是否计入 surfaces 待 REG-3 确认 |

未列入 surfaces：`PrototypeHome`/`PrototypeDetail` 等 UI Widget、`PrototypeWebGuard`/`PrototypeResourcePolicy`/`PrototypeSchemeLoader`（策略与加载辅助）、模型类 `PrototypePage`/`Version`/`Feedback`。若 analyzer 扫描把「宿主目标上的公开类」扩到 Module 以外，以 REG-3 实测为准。

**surface 数：4** · **成员合计：20**

## 2. 成员清单

### `PrototypeStore`（8）

| 成员 | 种类 | 位置 |
|---|---|---|
| `pages` | method | `packages/prototype_module/lib/src/prototype_store.dart:76` |
| `versions` | method | `packages/prototype_module/lib/src/prototype_store.dart:91` |
| `version` | method | `packages/prototype_module/lib/src/prototype_store.dart:100` |
| `feedback` | method | `packages/prototype_module/lib/src/prototype_store.dart:118` |
| `feedbackById` | method | `packages/prototype_module/lib/src/prototype_store.dart:133` |
| `importBuild` | method | `packages/prototype_module/lib/src/prototype_store.dart:153` |
| `addFeedback` | method | `packages/prototype_module/lib/src/prototype_store.dart:246` |
| `specFor` | method | `packages/prototype_module/lib/src/prototype_store.dart:329` |

### `PrototypeRuntime`（4）

| 成员 | 种类 | 位置 |
|---|---|---|
| `receipt` | method | `packages/prototype_module/lib/src/prototype_module.dart:55` |
| `prepareImport` | method | `packages/prototype_module/lib/src/prototype_module.dart:57` |
| `commitImport` | method | `packages/prototype_module/lib/src/prototype_module.dart:62` |
| `openSession` | method | `packages/prototype_module/lib/src/prototype_module.dart:68` |

### `PrototypeSession`（4）

| 成员 | 种类 | 位置 |
|---|---|---|
| `resolve` | method | `packages/prototype_module/lib/src/prototype_module.dart:78` |
| `objectPage` | method | `packages/prototype_module/lib/src/prototype_module.dart:112` |
| `flush` | method | `packages/prototype_module/lib/src/prototype_module.dart:154` |
| `dispose` | method | `packages/prototype_module/lib/src/prototype_module.dart:156` |

### `PrototypeModule`（4）

| 成员 | 种类 | 位置 |
|---|---|---|
| `manifest` | getter | `packages/prototype_module/lib/src/prototype_module.dart:13` |
| `schema` | getter | `packages/prototype_module/lib/src/prototype_module.dart:16` |
| `routes` | getter | `packages/prototype_module/lib/src/prototype_module.dart:30` |
| `activate` | method | `packages/prototype_module/lib/src/prototype_module.dart:39` |

## 3. operations 表

| id | kind | members | 承载方式 |
|---|---|---|---|
| `prototype.query.pages` | `query` | `PrototypeStore.pages` | 已有工具: `prototype.list_pages` |
| `prototype.query.versions` | `query` | `PrototypeStore.versions`, `PrototypeStore.version` | 已有工具: `prototype.page_detail`（含版本列表与详情；与 list_pages 分工见缺口） |
| `prototype.query.feedback` | `query` | `PrototypeStore.feedback`, `PrototypeStore.feedbackById` | 已有工具: `prototype.page_detail`（页面详情含反馈）；专用 list 工具待 REG-3 确认是否需要 |
| `prototype.import_build` | `write` | `PrototypeStore.importBuild` | notExposed: `humanOnly` — 选本机目录导入构建版本，须用户在界面挑选路径，Q10/ADR §10 建议不对助手自动开放。 |
| `prototype.add_feedback` | `write` | `PrototypeStore.addFeedback` | 建议新增工具（尚未注册）: `prototype.add_feedback`（Q10 确认可开放为 write） |
| `prototype.web_spec` | `internal` | `PrototypeStore.specFor` | notExposed: `notBusiness` — 生成 RestrictedWebViewSpec 供 WebView 导航，属 UI/宿主桥接细节。 |
| `prototype.runtime.receipt` | `query` | `PrototypeRuntime.receipt` | notExposed: `humanOnly` — 导入回执供人工确认页展示，助手自动消费易跳过审核。 |
| `prototype.runtime.import` | `write` | `PrototypeRuntime.prepareImport`, `PrototypeRuntime.commitImport` | notExposed: `humanOnly` — 选目录导入流水线与 `importBuild` 同类，Q10 建议人工完成。 |
| `prototype.runtime.open_session` | `internal` | `PrototypeRuntime.openSession` | notExposed: `notBusiness` — 打开模块会话的生命周期 API，由宿主激活路径调用。 |
| `prototype.session.resolve` | `query` | `PrototypeSession.resolve` | notExposed: `notBusiness` — ScopeResolvable 解析实现，由宿主范围管道调用而非助手工具。 |
| `prototype.session.object_page` | `query` | `PrototypeSession.objectPage` | notExposed: `notBusiness` — 对象页描述供壳层渲染，非助手业务工具面。 |
| `prototype.session.lifecycle` | `internal` | `PrototypeSession.flush`, `PrototypeSession.dispose` | notExposed: `notBusiness` — 会话刷新与释放，由宿主生命周期管理。 |
| `prototype.module.contract` | `internal` | `PrototypeModule.manifest`, `PrototypeModule.schema`, `PrototypeModule.routes`, `PrototypeModule.activate` | notExposed: `notBusiness` — BusinessModule 清单/schema/路由/激活，属模块注册契约而非业务操作面；若 REG-3 将 Module 类排除出 surfaces，本操作可整体删除。 |

**操作数：13**

## 4. 缺口汇总

### 需要新增工具才能覆盖的操作

- `prototype.add_feedback`（write）— Q10 已确认可开放；当前仅有 `prototype.list_pages` / `prototype.page_detail` 两个读工具。

### 归 `internal` / `humanOnly` / `notBusiness` 的成员及理由

- `importBuild` / Runtime `prepareImport`+`commitImport`：`humanOnly`（选目录导入）。
- `specFor`、会话/模块生命周期成员：`notBusiness`。
- `receipt`：`humanOnly`（导入回执人工确认）。

### 拿不准的归类（待 REG-3 确认）

- 源码中**未见**独立的「删除页面/版本」公开方法；ADR 文案提到的删除 `humanOnly` 暂无对应成员可挂——待确认是否在 UI 层直接 SQL、或尚未实现。
- `PrototypeModule` 是否应出现在 `surfaces`（契约类 vs 业务操作面）。
- `versions`/`feedback` 是否已完全被 `prototype.page_detail` 覆盖，或需只读专用工具。

### 统计（初稿）

- surfaces: 4
- members: 20
- operations: 13
- 建议新增工具数: 1（`prototype.add_feedback`）
