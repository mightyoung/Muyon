# AI-native 下一批任务 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task after leader review. Steps use checkbox (`- [ ]`) syntax for tracking. 不因模板建议自动新派代理；沿父任务已经指定的执行与独立审查方式。

**Goal:** 先交可操作的 Flutter Web 预览及云端 UI/业务流程验收，再按最小契约接真实询价、持久返回、导入、导航与子对话。

**Architecture:** 复用现有 Flutter v6 UI、领域服务、SQLite、注册/授权/回执与任务内核；Web 预览独立入口和公共夹具，主应用不改框架。语义合同和确定性 Runtime共用；Intelligent UI 与 Motivation UI仅替换规划 Provider，既有大模型/夹具可先推进。

**Tech Stack:** Flutter3.47.5/Dart3.13.4，现有muyon_ui/module_api和宿主；云浏览器核查报告为Chromium151/Playwright1.62.1/Node24.19。云Flutter/Dart缺失，官方SDK安装批准仍等待，当前不安装。

**Spec:** 架构分支 `docs/ai-native-architecture-20261008` 固定66476e2f3ec44e09c4990b4e7997e8c990fccae0，实际路径为 [整体设计](../specs/2026-10-08-ai-native-architecture/Muyon_AI_Agent与智能交互整体设计方案.md) 和 [原实施建议](../specs/2026-10-08-ai-native-architecture/2026-10-08-agent-platform-implementation-plan.md)。本计划v0.1吸收本轮用户新要求，不改原架构稿/已采纳ADR；仍待leader复核，未派编码。

## Global Constraints

- 固定已发布基线00dbd6cf722ddd4b5f7e8c65ec378ee4150fada9：AUTH C1/C2已包含ffe6be31，发布CI37792414130成功；不重做REG-2/AUTH/JR-1/UI-1a/K-1至4。
- 原ADR-0005初值继续：压缩0.8，最近2个用户回合且至少6条消息，每卡最多5调用，摘要上限2000token；不静默改指标。
- 云端先验收UI和业务流程，发现问题修复后可进入下一阶段；原生与实机集中最后，不逐片阻塞。云未覆盖能力必须标待验，不能称全部产品/三端通过。
- 首片交可运行预览，不只JSON合法率；现有壳和固定业务页保留，不以Web预览为理由迁完整主宿主。
- 本地优先、可选远端、已有数据库和领域规则保留；不新增生产微服务、第二模型网关、平行授权/任务/回执系统。
- 预览仅公开/合成夹具，UI明确模拟；云CI真实Host/SQLite业务测试与浏览器模拟动作分别记证据；不公开真实数据或把密钥写进静态包。
- 当前Mac例外仅限用户接受的46基线失败、184PNG一致，根因未知，后续回归见[备忘录](../../tasks/VERIFICATION-MEMO.md)，不可自动沿用到新SHA/新失败。
- 两模式共用契约/组件/校验/状态/事件；不预设在线功能更少。小模型统一/双模型、A2UI/GenUI仍评估，均不是主线硬依赖。切模式不能扩大外发授权。
- 指南只从train/dev提炼，封存test；适用条件、反例、证据、验证状态齐全，属于软建议。组件实际能力、绑定和现有权限才是硬约束。
- 父独审题面映射25组件：3通用Widget可复用、14需适配、8缺完整实现，全部缺动态接线。首片只做比较/试算的最小集；uix-01/02/03未审核为gold，不记成功，也不等题面全部完善才能写计划。

## Review Focus

1. 条件/视图已更新但规划仍拿旧current版本 → UI-3a/4a/4b用base4→next5与actualcurrent5测试。
2. 人工编辑后补丁/刷新覆盖qty12 → UI-3b及REG-4b保覆盖层，显式采用才换值。
3. 提交超时已经成功、重复点击或payload引用失效 → REG-4b/UI-4b核真实回执、冻结记录集合与host操作键，不重放。
4. 目录/schema/插件变化后仍有可点击旧动作 → UI-3a/4a/UI-2a显式只读退路，仍可返回。
5. 来源冲突或原文段落版本变化被布局掩盖 → UI-3a/4a保持unknown/conflict、失效定位与文字，不以模型复述代替证据。

## 首批与依赖

| 编号 | 可独立交付 | 硬依赖 | 复核后状态 |
|---|---|---|---|
| [UI-3a](../../tasks/UI-3a.md) | 最小语义合同+真实可点Web预览 | 现有UI-1a/REG-2/AUTH | 第一编码片，待派发 |
| [REG-4a](../../tasks/REG-4a.md) | 现有询价V2纯适配、真实Store差分 | 已合REG-2/AUTH | 已完成，develop `5a243c6`；CI `37883647998` 通过 |
| [UI-4a](../../tasks/UI-4a.md) | 确定性动态组合+受控云URL交互验收 | UI-3a；REG-4a业务联调 | 第一批云出口，待派发 |
| [UI-4b](../../tasks/UI-4b.md) | Harness自动/显式共用planning+两Provider入口 | UI-3a/4a | 不等训练/指南，待派发 |
| [UI-3b](../../tasks/UI-3b.md) | 草稿持久、人工覆盖、返回现场 | UI-3a/4a | 可与规划接线错开，不等模型，待派发 |
| [REG-4b](../../tasks/REG-4b.md) | 既有导入plan/apply、部分入库/续办 | REG-4a、UI-3b/4a | 进行中，`task/reg-4b-inquiry-import-pipeline`；本机/独审推进，云UI及实机待验 |
| [UI-2a](../../tasks/UI-2a.md) | 跨插件对象/文件导航与原位返回 | UI-3b、REG-4b | 之后，待派发 |
| [UI-4c](../../tasks/UI-4c.md) | 一层子对话与最新成果引用 | UI-2a、UI-4b/3b | 最后按闭环，待派发 |
| [C4-GUIDE](../../tasks/C4-GUIDE.md) | train/dev指南稿与可空检索接口 | UI-3a数据稿；UI-4b接口接入 | 云数据线程起草/接口待派，不阻塞上表 |
| [R-1-AI-UI-final](../../tasks/R-1-AI-UI-final.md) | 末次原生/实机与Mac截图回归 | 已完成相应云切片 | 并入R-1末次，非中间门槛 |

REG-4c完整新检索仍遵ADR在REG-4b之后；本次先用已有询价能力和公开比较夹具，不借试算题偷偷做全检索产品。REG-3科研/原型迁移、T-3/S-1、REG-5继续原任务，无重复新建。E-1/R-1续现有评测器和证据，不重复造一套。

## 云Web兼容核查与覆盖分界

| 已查来源 | 事实 | 最小处理/待验 |
|---|---|---|
| apps/muyon/lib/main.dart、bootstrap | 直接dart:io/MuyonHost.open；apps/muyon/web不存在 | preview独立入口，不导bootstrap，不称主app已Web兼容 |
| muyon_ui/catalog、primitives、confirmation、theme | Flutter组件为主，实际目录已核 | 首片编译/浏览器验证后才称可复用，缺部件做小适配 |
| muyon_module_api总入口、storage/tools/change_log | SQLite类型被导出，纯ObjectRef/ArtifactRef已有 | 新ui_contract纯入口隔离；Web构建smoke查传递依赖，不先搬整个存储层 |
| supplier/inquiry/research领域Store | 现有SQLite/文件服务 | 云Linux真实host/Store测试；浏览器内存公共夹具分列 |
| document_parser、paddle_ocr_service、file_gateway | IO、原生OCR/ONNX、文件权限依赖 | 云public预提取夹具展示流程，实际解析/OCR/权限未覆盖列末次原生验 |
| ModelGateway/secret/transfer/platform桥 | 宿主凭据/网络/平台能力 | 浏览器不嵌凭据；规划fixture可换现有授权模型，桥/传输实机待验 |
| 云/workspace/Muyon | 父提供：干净，Node/Playwright/Chromium可点图；无Flutter/Dart | 现有已批准SDK构建包或待批准官方云SDK；实际URL/访问控制仍核，不安装/不虚构已部署 |

云门禁至少包含构建包SHA/目录与合同版本、真实可访问的受控预览、移动/桌面操作自动化和截图、实际Host业务夹具结果、模拟/未覆盖矩阵。静态JSON或合成HTML点击成功不足以宣称Flutter云验收通过。承载无法核实时，交构建包与明确阻塞，其他不依赖部署的契约/适配工作继续。

## 共用planning与指南交接

输入是完整本次问答和实际上下文、current view版本、事实快照、组件/动作目录、Intent以及可选指南。输出是显示decision联合UIPlan；UI-3a校验事实/节点/动作/运行状态及计算结果/原文段落，UI-4a运行，UI-4b将三路事件回harness。自动展示规划与在线大模型显式请求共享接口/去重键，失败保文字、对话可继续。

Intelligent UI（本地小模型）和Motivation UI（在线大模型）按相同场景测功能、延迟、联网、成本与任务效果，不定义谁功能少。GuideEntry保持proposed/evaluated和证据，未验证启发式不成为规则引擎；无指南仍可规划。小模型成品必须接此port/harness和模型可见schema，不只是离线bench文件。

## 收束、回滚与后续派发

本次10份任务书只是可派发草案；未实施、未部署、未训练，也未将云未覆盖项写通过。首片实现可从UI-3a开始：纯合同/目录最小映射/公共比较夹具/可点击Web，不改主app、业务存储或授权。不等SDK审批即可完成纯Dart设计与现有已装SDK环境的单测规划；实际云安装等批准。

- [ ] leader先复核本计划、任务编号与接口、云模拟分界；其后逐片派发。
- [ ] 每片先行为RED、最小实现、目标测试、云UI/流程复验及独立review；修复后推进下一片。
- [ ] 新功能flag可关回原页/文字，不删除历史数据、来源、人工覆盖或成功receipt。
- [ ] 最后集中原生与实机验收，保留未测；不将某次Mac例外延展成一般放行策略。

本计划不发布到develop，不动main/release；父复核后才进入编码。
