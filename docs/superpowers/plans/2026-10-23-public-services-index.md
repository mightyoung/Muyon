# Muyon v0.2 公共服务 Implementation Plan 总索引

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已认可设计拆成可独立审查的交付片，当前只提交文档，等待用户审阅实施计划。
**Architecture:** 复用 Rust 可信 owner 与原 IntentId/Receipt，Kotlin 只承接平台引擎和展示。公共合同只适配，不建立第二账本；三个业务插件保留各自领域规则。
**Tech Stack:** 现有 Rust/serde/SQLite、Kotlin/Compose/UniFFI；旧 Dart 仅语义参考；Electron UI 框架未选。
**Spec:** [已认可设计全文](../specs/2026-10-23-public-services-ui-design.md)。

## Global Constraints

- 外部应用、服务和 API 接入统一称 Connector；MCP 是协议，业务插件是领域模块。
- 旧 Dart 合同仅供语义迁移参考，不恢复 Flutter 路线。
- 注册不执行、不授权；Skill 只能收窄能力，包中脚本不执行。
- 只读请求不得顺带启动解析、OCR、下载模型、索引构建或付费模型调用。
- Reader Core 生产 FD 桥保持原安全检查阻断，不以 URI、路径或另建桥绕过。
- 历史真实请求 unknown 与费用未知保持；本轮不安装依赖、不调用模型、不连接真实账户、不部署。
- 计划中的类型、路径和测试若注明“新增”，均尚不存在；接口是评审候选，不能据此宣称已冻结或完成。
- 本计划整体经用户评审并批准执行后，范围内任务按已选并行方式推进，不逐任务重复索批；新增范围、独立工程决定、受阻操作或必须逐次确认的行为另行处理。本分支只允许 docs 下的 Markdown。

## Review Focus

1. 原 lookup 特例 not_submitted 不能被当作可重放 unknown：C2 测试固定。
2. 旧 Long/UI 页码与公共十进制/0 基页码不一致：U1 测试拒绝截断和错误页码。
3. 旧索引只有 paper/project 身份，不能冒充公共 ResultRef：D2 兼容测试拒绝无来源旧条目。
4. Skill/Connector 元数据变化与权限变化不同：S2、X2 测试保持权限交集并拒旧 prepared。
5. Agent 完成或旧 SHA 的 CI 成功不能代表研发验收：B3 固定 SHA 证据走查与 B4 后续测试。

## 基线与来源

2026-10-23 在已保存 Muyon 云端环境读取。初始检出 `work` 为 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`；它是旧 main 合并点，未用作产品基线。普通 `git fetch origin develop` 成功写入 FETCH_HEAD，因原 remote.fetch 只映射 main，没有生成 origin/develop；本次明确以 FETCH_HEAD 的完整 SHA 建候选分支：

`7aa852ab8134545c6312cd71de5c12cd49f66b5b`

候选分支：`docs/public-services-v02-plans-20261023`。未切换或修改 main/develop。扫描 /workspace 及 develop 文件树未发现 AGENTS.md，已读 `docs/tasks/README.md`、`REVIEW.md`、`CURRENT-STATUS-2026-10-10.md`、`HANDOVER-LEADER.md`、`android-agent-handoff-owner-20261018.md`，以及 `evidence-local-chain-20261022/HANDOFF.md`、`ui-action-cards-20261022/REPORT.md` 和卡片 README；另读 `ui-shell-20261022/REPORT.md` 及普通聊天 `ordinary-chat-live-20261019/REMOTE-CREDENTIAL-HANDOVER.md`，保留已记 unknown/charge unknown。旧交接中 Flutter 阶段、角色、已通过记录均是历史，不恢复旧执行授权。

评审页：[v0.2](https://chatgpt.com/space/page_1ec6e1b403bc8191a625c4b74011409d)；补充研究：[Connector/Skill](https://chatgpt.com/space/page_40345e6f0bdc8191808b06392911ebb7)、[Linear 领域生命周期](https://chatgpt.com/space/page_e3d95dbf83c08191b1c8e006bd1ff23a)、[研发独立设计提案](https://chatgpt.com/space/page_c3e02abcc00c8191a4353c4338faa0ea)（待评审、未实施）。均已只读获取；设计全文保留页面的用户认可记录。研究中的 operationId/Outbox 建议由后来的 v0.2 原 IntentId/Receipt 约束覆盖，不引入新账本。

## 独立计划、依赖和唯一 owner

下列 owner 是任务角色，尚未指派人员；同一文件只能由表中角色修改。接口使用方不得顺手改公共文件，需向 owner 提交 fixture 或变更要求。

| 计划 | 任务与 owner | 文件唯一归属 | 依赖 |
| --- | --- | --- | --- |
| [公共合同与原回执](2026-10-23-public-contracts.md) | C1/C2/C3，Contracts | 新 services/types.rs、commands.rs、drafts.rs、mod.rs；types/commands/drafts fixtures；core lib.rs 模块登记；FFI lib.rs 唯一接线修改者 | C1 → C2 → C3；FFI 接线等 B 的内核审查完成 |
| [统一 UI 与 Intelligent UI](2026-10-23-intelligent-ui.md) | U0/U1/U2/U3，PublicUI | 新 UI 设计/页面验收文档、product/ui/publicservices 与同路径测试；现有 cards 与 foundation 文件的后续变更 | C1、C2、U0 具体变体评审；Shell 所有权交接后才接页面 |
| [资料处理与来源](2026-10-23-document-pipeline.md) | D1/D2/D3，Documents | 新 services/documents.rs、pipeline.rs、sources.rs；新 product/services/documents；既有 ml 引擎文件；文档测试 | C1/C2；D3 生产 FD 前置阻断 |
| [Skill 注册与运行](2026-10-23-skill-runtime.md) | S1/S2/S3，Skills | 新 services/skills.rs、skill_runtime.rs 与 skills fixture；新测试；现有 agent/workflow.rs 的后续接线 | C1/C2；与内核 owner 交接后才改 workflow |
| [Connector 与 MCP](2026-10-23-connectors.md) | X1/X2/X3/X4，Connectors | 新 services/connectors.rs、connections.rs、后续 mcp.rs 与 connectors fixture；新测试与候选评估记录 | C1/C2；SDK 与凭据设计 gate；GitHub/GitLab/Gitee 同步先做能力/事件设计，真实连接后置 |
| [三业务插件与研发全周期](2026-10-23-business-plugins.md) | B1/B2/B3/B4，Domain | 新 domains/ 下科研/询价模块与测试、plugins fixture；研发设计/依赖文档；research.rs/business.rs 的后续适配；领域 migration | C1/C2/U1/D1；自动化再依赖 S2/X2；研发 B3 提案评审后才写一期执行计划 |

Contracts 独占 `services/mod.rs`、`crates/muyon-core/src/lib.rs`、`crates/muyon-android-ffi/src/lib.rs`；其他 owner 只交付独立模块，登记由 Contracts 串行小提交完成。Domain 独占业务 Operation 变体与数据库迁移，须与 Contracts 联合审查并串行提交；C1 不改现有 Operation。S1/X1 snapshot 元数据写入也需原命令 owner 明确 variant，不能绕过授权链。禁止两个任务同时改 SQLite schema version。

Shell 任务 `01a161b7-eeb1-7502-943d-1f8309a4b012` 继续修现有页面，本计划不修改其产品文件。内核候选 `task/bot-core-continuation-20261023` 固定 `22fce87436473ab7b894a26cde339be0546376a3` 由 B 任务 `01a14fbb-c8ec-7215-9b01-9c8cebf140d7` 唯一审查/合入；它不是本分支父提交，不复制或再次实施该候选。

## 分期及停止条件

| 阶段 | 可独立交付 | 明确后置 |
| --- | --- | --- |
| P0，当前 | 设计、六份计划、总索引与自审；无产品实现 | 用户尚需审阅计划 |
| P1，评审后可先做 | C1/C2 纯合同/投影，U1 白名单校验，D1 既有本地文本只读适配，S1/X1 本地目录，B1/B2 科研/询价投影与合同；研发 B3 设计承接 | 所有生产 dispatch 默认关闭；不安装 SDK |
| P2，依赖满足后 | C3 草稿 CAS，U2/U3 组件和无障碍，D2 任务及来源验证，S2/X2 假 owner 的授权/恢复，B3 固定证据/发布记录/反馈及对话建项设计走查（文档） | 使用 mock 的结果只能标 synthetic；不据此宣称端到端上线 |
| P3，另审工程决定 | D3 原授权 FD 桥解除后接生产引擎；S3 parser 评估；X3 MCP 固定包评估、X4 三方仓库同步设计；B4 获批后细化研发一期与扩展阶段 | 真模型、真实 Connector、外部写入、PR 合入、发布部署、任意脚本、完整 Office 编辑及桌面框架另行授权 |

## 规格覆盖与端口方法去向

| 设计章节/验收 | 实施任务 | 当前未交付部分 |
| --- | --- | --- |
| §1–3 分层、版本、scope、资源、计量 | C1，D1/D2 | 账户级宿主绑定与配额工程 gate |
| §4 DocumentPort 全清单、Office 能力矩阵 | D1/D3 | 导入/新版本/解析命令及 Office 发布依赖原 owner 扩展，P3 |
| §4 OCR/Embedding/Index 全清单 | D2/D3 | 引擎生产接线、查询向量授权及快照持久化 P3 |
| §4 TaskPort、DraftPort | C2/C3、D2 | JobId 子任务取消不开放；泛领域持久草稿 rollout P2 |
| §4 HostCommandPort、§6 回执恢复 | C2、X2、S2 | 新 Operation 不能借 JSON 任意派发 |
| §4 SkillRegistry 全方法、Runtime 三个 getter/requestRun | S1/S2/S3 | 安装可执行扩展不在本轮架构实施范围 |
| §4 ConnectorRegistry 全方法、Connection 全方法 | X1/X2/X3 | 真实 consent/token revoke/remote 读取 P3 |
| §5 全链路、不可变版本、删除及跨 scope | D1/D2/D3 | 历史原文可用性不能由索引保证 |
| §7 六份内容、事件、四轴状态 | U1/U2、C3 | 桌面 renderer 后置 |
| §8 十族、槽位、视觉与附属组件 | U0/U2/U3 | 地图/任意 HTML 不列首批 |
| §9 科研/询价/研发、Bot | B1–B4、U2 | createAgent/startTask 保持独立；Bot 页面布局仍待评审 |
| §10 协商、生命周期 | C1、S2、X2、D2 | IDL/生成器、订阅生产容量待工程 gate |
| §11.1–8 | C1–B4 各测试及 U3 验收矩阵 | 本轮没有执行这些产品测试 |

## 执行与证据协议

每个任务使用独立分支，开始时重新读取 develop 和上游任务最终完整 SHA；发现接口漂移先更新计划，不从 main 或未审候选开产品基线。输入只允许本地合成 fixture，清除真实模型执行开关；命令使用 `--offline --locked`，缓存/toolchain 不足即标 BLOCKED，不安装。

每任务均按 RED → GREEN → 回归 → 独立审查提交。RED 必须在测试存在且导入/编译通过后观察目标行为失败；新增 API 初次“符号不存在”仅是结构 RED，不能代替行为 RED。必要时先加明确返回 unavailable 的最小 stub，提交测试/stub，再观察具体断言失败。GREEN 不能通过弱化断言或把 unknown 改 success 达成。Rust 命令从仓库根执行；Kotlin 新纯 JVM 检查复用现有 run-offline.sh 编译器发现方式，缺工具停止。所有表中 Expected 是未来预期，不是本轮结果。

证据摘要写入每任务 `docs/tasks/public-v02-<任务>/REPORT.md`：完整 RED/GREEN/source SHA、命令、退出码、断言/测试计数、fixture 摘要、平台、测试范围、未运行项、审查人及 findings。原始日志保留仓库外并记录 SHA256，不提交日志；含实际身份/费用的记录不复制进测试 fixture。编译、模拟、设备、真实外部效果分别标注，缺结果写 NOT_RUN，不填零。

每片回退：禁用新入口/撤销新 prepared，保留原回执与未决 IntentId，由原 owner 收束；正常 revert 对应提交，不删分支、不 force、不降 schema、不删除旧记录。持久化升级使用加法表，原数据不覆写；回退前先导出最小审计和失败草稿，未知外部效果继续 lookup。只有 B 可合 develop，本任务不创建合入操作。

## 文档自审记录

已逐章对照设计，并检查六份计划的输入/输出及 owner。新类型集中定义或在所属任务明确声明，existing 与 proposed 分开；`DocumentRef`、`Revision`、`Operation`、`ExecutionResult` 沿用原类型。发现并修正规划风险：lookup not_submitted 特例、旧 UI 的 Long/1 基页码、现有 ResearchIndex 的科研身份限制、Linear 旧 operationId 建议冲突、Job 不存在统一枚举、SDK 许可未核、Reader FD 阻断。未把这些缺口记为产品已修复。

保留工程 gate：账户级身份来源、订阅容量/游标持久化、UI 具体尺寸/变体与页面组合、三方仓库能力差异、对话候选归属/差异确认、资源配额/缓存淘汰、IDL 生成器、桌面框架、引擎选型/许可及 Android 兼容。各 gate 见 U0/D3/S3/X3/X4/B3/B4；进入相关生产任务前先交付具体工程决定和测试，不能把未知项交给执行者默认猜测。计划自审不等于独立审查批准，也不授权实施。


## 本轮实际文档检查（不含产品测试）

- 8 份 Markdown（设计 1、独立计划 6、索引 1）：相对文件链接存在、代码围栏成对、全部计划含 writing-plans 要求的头部和 Review Focus。
- 新增 API 与现有 API 分开标注；自审已修正 SupplierRecord 无 project_id、StoreEvidence 无全文 getter、确认重复可能返回 lookup 特例、UI 实时撤权需当前 access 输入的签名缺口。
- 全文规格覆盖见上表；所有未实现项明确写入阶段/gate；研发新增设计保持 proposed，三方持续同步和渐进对话建项只列依赖与评审场景。
- 本轮只运行 Git/文件/Markdown 静态检查。RED/GREEN、Rust/Kotlin 编译、真实模型、设备、Connector、CI、部署全部没有在本轮执行；计划中的预期通过不记为结果。
- 独立审查仍待用户/合入者；本分支未申请自动合入。当前没有自动审批拒绝或结果不明的写入动作。
