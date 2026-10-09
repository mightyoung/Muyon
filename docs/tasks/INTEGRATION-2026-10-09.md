# 2026-10-09 develop 集成复核

唯一 develop 合入执行者；用户最新授权为“同时将多个已提交分支再检查一下后并入develop”。
基线 `01404ae472451f55af5baa6ce76c95af72b0cbfc`，main
`cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` 保持不动。独立云工作区
`/workspace/Muyon-integration-20261009`，已读 HANDOVER-LEADER A–D、REVIEW、
ADR-0001 用户决定、产品架构总览、AI 原生方案及流式契约。未找到 AGENTS.md
或 .agents/skills。没有修改产品设计、远端分支删除、强推、自动合并、部署或打包。

## 冻结候选与决定

| 候选 | 完整 SHA | 复核及门禁 | 集成决定 |
|---|---|---|---|
| GROK-7 | `18ae5127474d6841ad331ca2251076ecca431a81` | [独立审查](GROK-7-review.md)；[精确CI](https://github.com/mightyoung/Muyon/actions/runs/37948032314) success | 先合文档，四处勘误/边界澄清，不改设计 |
| REG-3a | `48b36375c2ea8ebf3c10281e7f6372a9aa52e5b7` | [独立复审](REG-3a-review.md)；[精确CI](https://github.com/mightyoung/Muyon/actions/runs/37961770816) success；host +1267 ~3，8/8 analyze、8/8 suites | 两模块有界 v2；精确工具目录例外获准，保留行为检查 |
| PR #6 | `107ca439547a01c4ac37e218e059de0a508a0309` | [独立审查](CI-PACKAGE-review.md)；本轮重跑 26 Python tests OK | 仅手动基础设施，不执行 workflow_dispatch |
| AIUI-1 | `276b29146d3eb902380cceac708209cc6ef344c0` | [独立复审](AIUI-1-review.md)；[精确CI](https://github.com/mightyoung/Muyon/actions/runs/37952681084) success | 父任务已转交审计无新确定协议/授权阻断结论；加入组合门禁，成功才发布 |
| AIUI-2 | `3f739035385b7640d1fcec497dc33a85d3553ffe` | [精确CI](https://github.com/mightyoung/Muyon/actions/runs/37963507853) success，Form 修复已验 | 暂缓：Tabs 缩减列表后索引未调整（layout.dart:214/271），原执行者修复中，不合旧 SHA；typed edit/detail/集合与恢复接线归后续，不弱化 validator |

临时组合 `53458c6c69b8aff9c5338d8b7d28417a547706c8` 包含 GROK-7 与 REG-3a；
[CI 37965251000](https://github.com/mightyoung/Muyon/actions/runs/37965251000) 已到
completed/success；analyze 8/8、test 8/8、module_api +38、host +1284 ~3。
PR #6 相对该组合只增四个基础设施文件及审查摘要，另由精确源码离线测试验证。
收到全库审计明确结论后，另将 AIUI-1 加入完整组合并重跑 CI；前一次运行不代表
含 AIUI-1 的组合已通过。AIUI-2 的 Tabs 复现/修复与新精确提交 CI 仍由原任务负责。
完整四项组合 `af7c8a47af1ca2f26796aa197ba6dd8065d8a982` 的
[CI 37966891011](https://github.com/mightyoung/Muyon/actions/runs/37966891011) 已到
completed/success：analyze 8/8、test 8/8、module_api +68、muyon_ui +193 ~60、host +1284 ~3。
发布前再次 fetch/ls-remote，develop 仍为冻结基线，无并发变化；本次最终增量仅为
本摘要、索引状态和 AIUI-1 复审措辞，不改组合已测的产品/基础设施文件。
最终 develop 发布完整 SHA、ls-remote 与对应 CI 终态在执行回报核对；不把临时 CI
冒称最终发布 CI。原始验证日志不入库。

## 排除项

- REG-4b `8025f66c80af9fc22ec7c60ff5f68ccdc1463a96` 和其 ABC 集成已是 develop 祖先，不重复。
- 已合 AUTH/UI/REG/agent_dispatch 等分支全部按祖先关系排除。
- `task/mascot-rive-probe` 仅 probe，不作为生产功能合入。
- `task/r-1-evidence` 仍有 Android 未完成；其 E-1 基线单独交付，不冒称 R-1 全完成。
- PR #4 / `docs/ui-design-authority-2026-10-06` 与 `claude/ui-framework-review-2863c3`
  已由后续设计采纳/替代；旧五导航方案不能重新盖过当前四导航。无自动合入。
- `docs/ui4c-agent-repair-preparation-20261009` 是未派发草案；不作为完成的开发交付。
- `feat/p0-ci-llm-baseline` 已停用；`task/p0-j1-env-doctor` 与 `review/P0-J1`
  的实现/审查 patch 已等价进入 develop，剩余旧任务文档不能当作新实现重复合。

## 留给父任务派发的无争用候选

1. **T-3 首片：平台只读自省。** ADR-0004 §10.1 前置 REG-2 已齐；本轮冻结时远端
   没有 T-3 任务分支/任务书或 platform 自省工具实现，不能声称完整 T-3 已完成。
   推荐先写任务书，再让非集成执行者实现新增 `apps/muyon/lib/platform/platform_tools.dart`
   和 `apps/muyon/test/platform_tools_test.dart`，必要时仅在 `app/bootstrap.dart` 加登记。
   复用 foundation_repository/task_records/execution_store/transfer_service 的只读数据；
   按同一 registrar 注册宿主 platform 身份。限定执行记录、记忆、通知、当前设备状态
   读取，不启动网络发现/发送，不读 secret，不直接标记已读或写记忆。
   验收：C-TOOL、参数和范围拒绝、read 纯度/DB 前后不变、脱敏和数量边界、无网络效应；
   analyze info 为失败、宿主全量和精确 CI。ObjectRef/范围语义须任务书明确，不扩原权限。
   首片不宣称完整 T-3（记忆候选提议另片）。不碰待合模块文件或 module_api/src/ui、muyon_ui。
2. **R-1 Android 剩余取证。** 最新 `task/r-1-evidence@a136e9f096c0373b5c4470e7a8bcabfa2c5c5102`
   已交付 E-1 真实模型 22 题基线，Android r1 证据仍缺；UI-0 已取消。由本机 engineer
   在已审查 develop、连接 vivo V2324A 与真实模型后执行一次 North Star；只写
   `docs/evidence/2026-10-p0/north-star-android-deepseek-chat-r1.json` 和
   `docs/implementation/p0-evidence-2026-10.md` 的 R-1 摘要。验收按 R-1/HANDOVER §5：
   如实记录 passed/readResultsChecked/逐题工具/防重放/运行 commit、凭据与路径脱敏，
   跑后卸载并核 pm list packages。不与契约/模块实现争用；手机/密钥只在本机使用。

父任务后续调度：T-3 首片已派 `01a121bb-56ad-73d4-8c92-25ce29bf2018`，
独立 `task/t-3-platform-read-tools`；bootstrap 登记另提交，本轮集成避开其文件。
R-1 暂不新增执行，待集成版与设备/真实模型条件确认。

## 工具与未验证范围

云环境缺 Flutter/Dart，官方下载被代理 CONNECT 403；没有绕过限制，没有 Mac 存储消耗。
gh REST/GraphQL Forbidden，但 git fetch/push/ls-remote 和 GitHub 连接器可用；
CI 查询用通用 github_fetch 的 workflow-run API（专用 commit-runs 工具只查 PR 事件，
空列表不能当作没有 push CI）。本地无 actionlint；包装原生验证明确未做。
本地另外重跑门禁退出码 9 项与 doctor 23 场景均通过，未导出 MUYON_EVAL_REAL。
Linux 门禁中 macOS 字体 golden 的跳过不构成 golden 验收；原有 Mac 失败结论保留。
REG-3b、剩余科研写入/Q10 本机导出门面、REG-5、AIUI 接线、真实模型/真机端到端另行处理。

## 第二轮：组件库与后续任务书

首批四项已发布 develop `36a516af6af92679fc47b79a1d4679c37258d030`，
[发布 CI 37968313166](https://github.com/mightyoung/Muyon/actions/runs/37968313166)
completed/success；analyze 8/8、test 8/8、module_api +68、muyon_ui +193 ~60、host +1284 ~3。

本轮冻结 AIUI-2 `4e45836efcb85c86f5c8de57e6b07795aab6166a`，替代上表暂缓旧 SHA；
[独立复审](AIUI-2-review.md) 和精确 source CI 均通过，Tabs 阻断关闭。
另冻结 `docs/aiui-next-batch-contracts@82df0f29d9628d107d96d52795438e972ce5fefe`，
[独立任务书复核](AIUI-NEXT-BATCH-review.md) 通过，只纳入四份任务文档。
两项本地正常 merge 无冲突；按组合 CI 成功→重核 develop→正常发布→精确发布 CI 终态执行。
任务书保留正式 schema 决议关口，不以文档合入代替实现或授权扩张；F3a/F5a 基础片可随后派发。

第二轮完整组合 `73e62c62c3a113635a91594f6c61339c5b5598dd` 的
[CI 37970211887](https://github.com/mightyoung/Muyon/actions/runs/37970211887)
completed/success：analyze 8/8、test 8/8 suites，module_api +68、muyon_ui +311 ~152、host +1284 ~3。
发布前 fetch/ls-remote 再核 develop 仍为 `36a516af6af92679fc47b79a1d4679c37258d030`，
main 保持原 SHA；本次收尾仅上述测试摘要和任务索引状态，产品/基础设施树与已测组合一致。
最终 develop SHA、远端复核和精确发布 CI 终态在执行回报给出。
