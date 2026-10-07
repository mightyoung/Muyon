# 设计稿 v4 审阅：与仓库文档、代码现状的对照

日期：2026-10-07 · 基线：`develop@ee39d58` · 稿件：[`docs/design/v4/`](../design/v4/)（Claude Design 第四轮产出，用户上传）· 性质：审阅与决定记录，不改产品代码。

## 0. 结论

v4 的视觉与交互已经成熟，安全语义大多画对，**作为第一阶段之后 UI 重做的目标稿**。前提有两个：

1. 稿里有一批后端尚不存在的**新能力**（§4），按 [ADR-0001](../adr/0001-leadership-and-scope-freeze.md) 范围冻结，排到第一阶段之后，且每项先定契约再做界面。
2. 稿与 [UI 重设计方案](../design/ui-redesign-brief-2026-10-06.md)、与代码之间有几处矛盾（§2、§3）。用户已于 2026-10-07 做出决定（§1），方案文档同日更新；需要设计方返工的部分写入[第五轮提示词](../design/v4/prompts/claude-design-prompt-round5.md)。

方法：在本地 Chromium 中渲染全部 17 个 `.dc.html`（React/Babel 取自 npm registry，SRI 与稿件一致），逐屏查看主要画面并切换部分状态；对照 `apps/muyon/lib`、`packages/*/lib` 与 `docs/design/`。没有逐页检查深色与 200% 字号。

## 1. 用户决定（2026-10-07）

| # | 事项 | 决定 |
|---|---|---|
| 1 | 底栏顺序 | **以设计稿为准**：AI 助手 · 业务插件 · 工作台 · 数据交换 · 设置 |
| 2 | 记忆入口 | **以设计稿为准**：记忆在「助手设置」；工作台只放「资料」卡片 |
| 3 | 状态色 | **设计稿方案 + 独立警告色**：待确认与选中同色系（tint + deep）；新增 `warn` token，深色值不得与 `deep`/`tint` 相同 |
| 4 | 助手确认语义 | **参考 ChatGPT、Claude、Muse，设多级权限、分级控制**。见 [ADR-0002](../adr/0002-graded-assistant-authorization.md)。同日确认：写入可设“始终允许”；外传可按已授权端点“本次对话”放行；先不做内容审查，留审查插件 / 服务接口 |
| 5 | 稿件入库 | 放入 `docs/design/v4/`（原样，不改稿件内容；返工通过第五轮提示词） |

## 2. 稿与仓库方案的矛盾（已按 §1 处理）

| 事项 | 方案（2026-10-06） | v4 稿 | 处理 |
|---|---|---|---|
| 底栏顺序 | … 数据交换 · 工作台 … | … 工作台 · 数据交换 … | 决定 1，方案已改 |
| 记忆入口 | 工作台卡片 | 助手设置 | 决定 2，方案已改 |
| 待确认颜色 | 琥珀 | tint（浅蓝 / 深琥珀） | 决定 3，方案已改 |

## 3. 稿内问题（交设计方返工）

| # | 问题 | 证据 | 级别 |
|---|---|---|---|
| F1 | **警告色无规格，深色与“选中”撞色**。`tokens.md` 只有红、绿；第三、四轮 5 个文件私定 `amb`，浅色 `#8A5A00/#FFF1D6`，深色 `#F5C27A/#3A2A12` 与 `deep/tint` 完全相同。`components.md` 的“警告条 琥珀”、报价徽标的 warn/info 色调在 `tokens.md` 中未定义 | `Muyon Inquiry Spec+Catalog`、`Exchange Hub`、`Platform Gaps`、`Desktop Spec`、`Desktop Inquiry` 的主题对象 | 应改 |
| F2 | **确认画法与代码不符**。对话页给只读工具 `inquiry.compare_quotes` 画了确认/拒绝；代码里只读工具在范围内直接执行，需要确认的是每次模型请求（`PersonalAgent` 的 `requestDigest`）。对话页没画模型请求确认。对话内工具卡只有“参数”，缺 `components.md` 规定的固定字段 | `Muyon Mobile` 的 AI 助手页；`apps/muyon/lib/assistant/personal_agent.dart` | 应改（按 ADR-0002 重画） |
| F3 | **工具 ID 多为虚构**。`inquiry.create_rfq`（代码为 `create_inquiry`）、`inquiry.accept_quote`、`inquiry.publish_hub`、`inquiry.quote_vs_budget`、`inbox.summary` 均不存在。现有写入工具只有 `create_inquiry`、`record_quote`、`set_item_qty`、`set_inquiry_status`（`apps/muyon/lib/platform/inquiry_write_tools.dart`）；只读工具见 `apps/muyon/lib/assistant/selection_eval/selection_set.json`。`publish_hub` 是新的外传动作，需单独评估 | `Muyon Assistant Settings` 规则详情 | 应改 |
| F4 | “外传”标签颜色不一致：收件箱为 tint，规则详情为红 | `Muyon Mobile` 收件箱；`Muyon Assistant Settings` | 可选 |
| F5 | 数据中心原型卡片显示“2 个对象类型”，与第四轮规则“原型没有对象类型、实例、血缘”矛盾 | `Muyon Data Center` 插件卡片 | 可选 |
| F6 | `round4-notes.md` 自报未完成：询价概览 / AI 任务 / 历史回答桌面版；旧稿 44 高控件未补 48 点击区；深色、320 宽、200% 字号未逐页查 | `round4-notes.md` | 跟踪 |

## 4. 与代码的对照

**已有代码支撑，属换壳（方案 UI-0～UI-10）：** 询价全部页面（数据中心、本体图、参数迁移 `param_migration.dart`、修改冲突、已删除的记录、阶梯价、定标、公司资料、命令面板、“历史回答，未保留查询依据” `ask_page.dart:771`）；平台的记忆与 Dream、离线工具、研究包导入、设备配对与传输、备份恢复、数据去向、MCP。

**新能力（代码中没有；冻结期不做）：**

| 能力 | 需要的后端工作 | 契约影响 |
|---|---|---|
| 分级授权（决定 4） | `ToolRegistry` 增加授权表与授权解析；模型请求按位置（`ModelLocation.local/ownDevice/remote`）分级 | 宿主内部；见 ADR-0002 |
| 助手权限四类开关 + 审计 | 按类别收紧助手可提出的操作 | 宿主内部 |
| SOUL | 存储、注入提示词、发往远程时入出站账本 | 宿主内部 |
| 规则配置（触发语句 → 接口） | 扩展 `RuleAndModelToolSelection`（`tool_selection.dart`）；规则冲突裁决 | 宿主内部 |
| 数据中心平台化：6 项检查、同步到助手知识库、示例问法评测 | 模块声明本体（对象类型、关系、查询接口、动作、流程）；知识库同步与回滚 | **`muyon_module_api` 新增本体声明**，改动最大 |
| 血缘 | 业务对象级来源与变更记录（目前只有记忆条目有 `lineage`，`foundation_repository.dart:47`） | 模块需提供来源记录 |
| 实例浏览器 + 敏感属性遮盖 | 敏感标记；后台遮盖需各平台接口（Android `FLAG_SECURE`、Windows `SetWindowDisplayAffinity`、macOS 窗口共享类型） | **契约新增敏感属性标记** |

## 5. Token 差异（交 UI-1 定稿）

| 项 | 代码 `packages/muyon_ui/lib/src/tokens.dart` | v4 `tokens.md` |
|---|---|---|
| 浅色底 | `#F7F8FA` | `#FCFCFC` |
| 深色底 / 面板 | `#111111` / `#191919` | `#0A0A0A` / `#141414` |
| 深色主色 | 蓝 `#7BA2FF` | 琥珀 `#F0A649` |
| 警告色 | `amber #9A5000 / #FFF2DF`（浅） | 无（决定 3 后补 `warn`） |

`warn` 暂定值（WCAG 公式计算，UI-1 用工具复核）：

| | 文字 | 底 | 对比度 |
|---|---|---|---|
| 浅色 | `#8A5A00` | `#FFF1D6` | 5.3 : 1（对 `sf` 5.9） |
| 深色 | `#E8C547`（色相 47°，主色琥珀 33°） | `#2E2A10` | 8.6 : 1（对 `sf` 11.0） |

规则：警告永远是 `warning` 图标 + 中文，不只靠颜色；深色下警告与选中靠色相与图标区分。

## 6. 后续

1. 第五轮提示词交设计方：F1～F5、按 ADR-0002 重画确认流程与「助手权限」页、补 F6。
2. ~~ADR-0002 两个待决问题~~ 已确认，ADR-0002 已采纳（2026-10-07）。
3. 第一阶段退出后，按方案 §9 分两条线派发：换壳（UI-0～UI-10）与新能力（每项先 ADR / 契约，再界面）。
