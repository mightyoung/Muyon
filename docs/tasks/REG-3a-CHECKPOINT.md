# REG-3a 阶段检查点

2026-10-09。AIUI-1 优先暂停后，父任务已划定文件边界并授权恢复。
本任务只提交、推送 `task/reg-3a-module-v2`；集成由父任务决定。

## 版本与环境

- 原工作树 `/workspace/Muyon`：`work@cc7c8d1`，保留未动且 clean。
- 独立工作树 `/workspace/Muyon-reg-3a`；建分支 develop 基线
  `b87a22b202cf0c3ce1c98aebb4df32af8d08d847`。
- 任务书 `9af1f6d30256f48924ec06355ae87ce348376c94`，
  [CI 37942959402](https://github.com/mightyoung/Muyon/actions/runs/37942959402)
  success：analyze 8/8、test 8/8；只证明该任务书提交与基线。
- 首实现 `2121ccfc9438208e89c8c2e0fe796a7c7f97d377` 已推送且核远端 SHA；
  [CI 37945525401](https://github.com/mightyoung/Muyon/actions/runs/37945525401)
  因后续修复推送而 cancelled；日志显示科研 analyzer 一个缺 braces 的 info，
  已修复。module_api/UI/prototype/research/supplier_core 五套测试成功，
  host 套件未完成；不能声称首实现 CI 通过。
- 最新 fetch develop `7559f23087754402f530b77672aa0081510e1b16`：
  GROK-6 草案/审查与 agent_dispatch 二次 effect 检查已合。
  本任务未修改 agent_dispatch，也未将新 develop 合入任务分支。
- Git fetch/push 成功；GitHub 页面与 connector 可读。
  本地 Flutter/Dart 缺失；官方 storage / api.github.com CONNECT 403；
  gh token 无效。本地 `scripts/ci.sh` 失败于 flutter not found / pub get。
  不绕过 Flutter 下载限制，原始日志只留 /tmp。

后续边界修复 `cf19dbc54a7d1a246b9f17d9bea8fcdded6f0bec` 已推送核 SHA；
CI 37947919276 已被 analyzer 修复提交取代。代码候选
`1e3de72ddac2c3c85ec56f26ccef6ff24621a322` 已推送核远端 SHA；
CI 37948049883 随本次交接文档更新被取代。最终 exact SHA 与 CI 终态
必须在父任务集成前重新核实；本文件记录提交时状态，最终运行证据见交付回复。

## 交付边界

- 科研/原型 v2、本体与有界覆盖清单；原三个读 ID/描述/顺序归模块 registrar。
- 科研 project 可解析，真实磁盘 bytes 摘要使旧引用失效；跨项目 session。
  原型无绑定对象页可打开，保留旧 `/` route 兼容保护测试。
- 科研 save_note / accept_run / assess_run / add_outline、原型 add_feedback；
  宿主掌握范围、审批、回执与撤销，事务内再次复核目标与 effect guard。
  真实新增 note 同事务记 change_log；no-op 不伪报变化。
- 宿主显式 reconsider 后重算静态策略；raw knowledge/models 仍 facadePending。
- 旧交换/索引/导入恢复/询价守护保留；REG-3b 不在本片实现。
- module_api 仅两个 additive 可选接口；未改 src/ui、公共导出、AIUI 测试。

## 独立静态审查与待验证增量

非作者 `/root/reg3a_static_review` 按 REVIEW.md 只读复核三轮。
最新轮未发现确定静态阻断，`git diff --check` 成功；没有 Flutter，未运行测试。
后续已提交增量：事务内 current-ref 守护、排队变更确定性屏障测试、
读取解析后同步复核、run-task revision 匹配、文档全文摘要复核与有界预览、
更完整的详情/关系/no-op/回执/双向清单/合法 OCR 重授权行为测试。
新增 widget 测试的真实异步激活、导入与工具调用使用 tester.runAsync。
ScopeResolver 会准备所有模块；工具调用也可能首次激活其他模块并进行真实 IO，
不能只包住原型激活/导入。CI 37948230181 因这项测试等待修复被后续推送取代。
最终非作者复核对象为 `1e3de72`，工作区 clean、
`git diff --check 9af1f6d..HEAD` 成功；未发现未解决静态阻断。
首实现 CI 无论结果如何，都不能验证这些后续增量。

## 明确未决与下一步

1. 首实现已到 cancelled 终态、日志 lint 已修复；最终分支 exact SHA CI 到终态，
   若失败读日志修复，不以静态审查或部分套件成功代替运行证据。
2. 独立审查最终提交；父任务协调与最新 develop / AIUI-1 的集成门禁。
3. 本片不是完整 REG-3：其余本机写操作在清单中 deferred(REG-3a-followup)；
   Q10 本机 exportReport/exportClaimDrafts 已获业务授权，但 registrar 缺本机
   目标选择/允许根目录门面，不能伪装成普通 write 或网络 external。
4. GROK-6 的 paper_binding、进一步字段/关系/卡片需后续落地。科研敏感度
   已由固定提交 002aef4e 正式批准为 none；真人 author 未来须 personal。
   现有本体有界覆盖 ADR 类型加真实 note，不宣称 GROK-6 全量约 68 字段完成。
5. REG-3b 交换与检索迁移单列；REG-5 通用 testing.dart / analyzer 门禁未做。
6. Linux CI 跳过的 macOS 字体 golden、真机/模型端到端未验证。

## 阻断修复恢复点

用户已授权从 clean task/reg-3a-module-v2@5ef48b7 恢复阻断修复。
该基线 CI 37952144103 success（analyze 8/8、test 8/8、host1261+3skips）；
本次新实现不能沿用基线通过证据。修复和新测试范围见任务书末节，
不会修改 AIUI src/ui 或保护 inventory 测试，不合 develop/main。
云端只读命令、Git fetch 与远端核 SHA 可用；本地仍无 Flutter/Dart SDK，
新提交推送后须最终 exact SHA CI 终态及非作者复审。
本次独立只读复审已消除屏障测试 schema 阻断，未发现其他确定静态问题；
本地 scripts/ci.sh 在 pub get 前因 flutter: command not found 退出，未运行测试。
