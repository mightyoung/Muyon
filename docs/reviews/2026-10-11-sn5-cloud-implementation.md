# SN-5 云端独立实施记录（I4 / I5 / M1，待统一复审）

本实施在独立云端分支 `task/sn5-handover-repair-cloud-20261011` 完成，不操作 Mac。原任务 `docs/tasks/SN-5.md` 的 Sonnet owner 历史保留；原分支不写入。本记录是执行证据，不是 Leader A / ChatGPT 的独立复审或合入许可。

## 固定来源与分工

- 原任务、CR12 复审、SN4 补充说明固定来源：`b6e4a4213c5b27a46e85c37f2682eab1419c5974`。PR51 不包含这三份文档，因此逐字补入；Git blob SHA 与来源一致，未改 owner / 原分工。原 `docs/tasks/SN-4.md` 保留。
- 本分支从 PR51 `d5cd97a13e9e7e00e7ffa0ced79d5f95b2b11d7e` 建立，完整祖先包括 SN4 `6d47da8a96f64d1c250987c13aab24b711322eb4` 和 SN2/SN3 `b6e185611a81853c99548d4528cd91cc8be36172`；均通过 `git merge-base --is-ancestor` 核验。未使用旧本机五提交实现。
- 开工与恢复前反复核远端：原 SN5 始终 `b6e4a421...`，未发现新 SN5 实施 PR / 分支；不据此断言所有外部任务空闲。
- 最新 develop 已从原观察 `f8cbd321d9607e8abe24b53f0b83c0911eaf9649` 前进到 `140a1b305271ca6a753bf6d2fd99f6b9c0e7c044`。新增范围 REG3/WC-D / 集成职责，无本任务重叠；只读核验，未导入 develop。
- Leader A 派发并组织 ChatGPT 统一复审，Leader B 为唯一 integrator，负责与最新 develop 组合、独验、合入。组合链为 PR42 + SN4 + PR51 + 本 SN5 + 另派 SN6。SN6 approval widget waitingConfirmation 挂起由 grok-build 处理；本任务不改该测试、不放宽或跳过断言，不诊断其实现。

## 实施范围

I4：workspace 保存独立宿主 `readOnlyProbe`，与恢复流程自身置 `readOnly` 分开；采用、恢复/丢弃入口、排队保存、保存前与恢复安装前检查实时宿主资格，探针异常按只读拒绝。surface 直接采用检查实时 `isReadOnly`。宿主负例用真实 agent / SQLite / DynamicWorkspaceSession，以 Completer 阻塞新 source；新身份同步建立、通知未到时旧采用/恢复/丢弃回调不改变内存、draftRevision 或持久化字节。单元测试计数 store.save，合法恢复/丢弃正例保留。

I5：_carry 重建当前可用候选目录；从旧历史移除旧 marker 对应及明确带 hostUiPlanningContext 标签的 system 消息，保留普通历史。新身份由 PersonalAgent 在新 model attempt 创建后、model.advance 读取 source 前冻结；成功恢复分支对尚未冻结的 manual attempt 冻结普通身份。真实 loopback JSON/native 各有 available / unavailable 控制：read → pause → resume，全部 system 消息无旧 surface/snapshot 广告，新候选 IDs 与 JSON/native 目录相符，新 source 元数据只出现一次，read 计数仍 1，未批准新模型请求。

M1：标准 router 和自定义 sink 共用 `uiTaskAcceptsEvents` 的 cancelled/interrupted 拒绝。真实 agent.cancel 后，保留 surface.dispatch 以及保留 sink 回调都不能发事件；interrupted 拒绝与 active 正例并列。无 preference 的实际入口证明拒绝不是被另一呈现撤权条件掩盖。

生产范围六文件：workspace.dart、surface.dart、agent_resume.dart、personal_agent.dart resume 段、ui_planning_events.dart、dynamic_workspace.dart。ui_planning.dart、inquiry_ui_planning_source.dart、PR51 ui_stream_task_view.dart/sn4_stale_ui_read_test.dart、personal_agent 原取消段均无 diff。测试为新增四文件，旧测试断言未改。无 CI / 门禁改动。

## RED → GREEN → 逆变异

RED 提交：`0b074f92f7cd531dfe441c71a753be0650b49fdb`。修复源提交：`40355501af1d545c9b0f584733f442321ce66d90`；后续记录提交只修新测试一处花括号 info 并记录证据。

- I4 单元 +2/-4：首项 Expected 9.0 / Actual 2.0；宿主旧采用 Expected '20' / Actual '12'，恢复/丢弃 Expected StateError / Actual future completed。新身份仍 source pending，旧通知未到。
- I5 JSON/native 四例首项 Expected empty / Actual old hostUiPlanningContext system message。
- M1 两例 Expected StateError / Actual future completed；active 控制通过。
- 初始宿主 fixture CAS 缺 revision+1、M1 缺实际 harness 的设置失败已修，不计行为 RED。另一次命令工作目录错误未计验证结果。

检出的逆变异（均 exit 1，随后源码逐字恢复）：

| 项 | 逆变异 | pass / fail | 首项行为失败 |
| --- | --- | --- | --- |
| I4 | 移除 surface 实时采用检查 | 0 / 1 | Expected 9.0 |
| I4 | 移除恢复宿主检查 | 0 / 2 | Expected StateError |
| I4 | 移除 controller 采用和保存宿主检查 | 0 / 1 | Expected save count 1 / Actual 2 |
| I5 | 保留旧规划 system 消息 | 0 / 4 | Expected empty |
| I5 | 不在 source 前冻结新身份 | 2 / 2 | Expected candidate assistant.plan_ui |
| M1 | 移除 custom sink 终态检查 | 1 / 2 | Expected StateError |

单独删除 controller 采用入口 guard 时仍被 surface / 保存层挡住，1/0 未检出；明确记录冗余防线，不冒称检出。上述 controller 完整防线变异检出保存调用。

恢复后相关宿主回归 76/0/0，UI 回归 23/0/0（pass/skip/fail），包括既有 resume、router、实时 workspace、SQLite 恢复和 quarantine 正例。补充 queued checkpoint 测试验证同步撤权后排队保存不能进入 store.save。全量门禁如下。

## 验证与限制

- 官方 SDK 源 https://github.com/flutter/flutter.git 的 3.47.5 tag 核验为 `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`，仅克隆/运行于 `/tmp/sn5-sdk/flutter`。`flutter --version` 确认 Flutter 3.47.5、Dart 3.13.4、引擎 `af7e796e161ae0bb1ff0758c71a7105418bd9ded`。tag checkout 因 detached HEAD 显示 user-branch，版本与 CI 固定 tag 一致。官方 archive manifest 当时 404，因此使用官方 git tag，未将推测 archive URL 视为已校验文件。
- SDK、pub-cache、分析缓存都在 /tmp；保留代理，NO_PROXY 包含 localhost。首次 analyzer 向只读 ~/.dartServer 写入导致 exit255，改官方支持 ANALYZER_STATE_LOCATION_OVERRIDE 后重跑；首次 host analyzer 发现新测试一处 curly-braces info，修正后重跑。最终八包严格 analyze 全部 No issues found / exit0。
- module_api 全量：198 / 0 / 0，exit0；muyon_ui 全量：385 / 152 / 0，exit0。平台/font 跳过为既有约束，不当作设备证据。
- host 全量：原命令 `cd apps/muyon && flutter test --no-pub --reporter expanded test` 已执行，但尚无终态，观察到 +639 ~2，最新 active 为原 aiui6_stream_approval_widget_test.dart。不写 host PASS；原测试未删/skip/改超时。日志 `/tmp/sn5-suite-host.log`，云端进程继续运行，后续由其真实终态补证。
- 原 SN4 run 38137228379 的早期只读核验已为 cancelled，实际 checkout 日志为 `6d47da8a96f64d1c250987c13aab24b711322eb4`；不当通过。本任务新 push / PR CI 的实际 checkout 和终态必须由远端日志独立核验，不能借用原 PR51 或 SN4 绿灯。PR51 后续诊断归原任务。
- 未运行真实模型、未导出 MUYON_EVAL_REAL、未操作 Android/adb/Mac，未安装系统组件、部署、合 main/develop、强推或删除。原始日志仅 /tmp，不入仓。
- 本分支未与 latest develop / SN6 组合；授权通知、hostTaintProbe、单项投影和取消超时后退路延迟清理的读/执行边界，由唯一 integrator 组合 CI 后组织统一复审。独立 GREEN 不能代替组合验收。
