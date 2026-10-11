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


## 独审 Important 回归补修：正常 native detach 的最后 checkpoint

独审在固定 `b4893004ddfbfb5a1e6a481b5668ec4cf96b3bf4` 指出：pane.dispose → session.detachWithBestEffortCheckpoint 同步捕获 flush 后立即 dispose；原 readOnlyProbe 绑定 !allowsPresentation，session._disposed 因此令排队保存误判撤权，抛错又被 best-effort 吞掉。await close 的正例不能覆盖此路径。

先独立复现，本地 RED 提交 `272a5baf2627c3a0d92b1ecb0e6619b981975786`，连接器同树发布 RED `9178a4cf423c5f3323bb28e3fafe965b8eba59a3`：真实 LoopFixture / agent / preference / DynamicWorkspaceSession / HostUiWorkspaceStore，直接 native detach、不 await close、不先通知保存最后呈现；首项 Expected last native view / Actual review。2 pass / 1 fail，取消先于 detach 与新身份在 detach 后同步建立的负例通过。检查最后 step、scrollOffset、selectedRecords、revision；用一轮 event loop 与 SQLite 写屏障等待已提交写入，无 sleep。初始取消负例基线包括取消监听触发的旧保存，已将基线取在取消结算后，不计该夹具失败为 RED。

修复只涉及 dynamic_workspace.dart 与 workspace.dart：

- 将 session 宿主呈现资格与 view mounted/disposed 分开；checkpoint 探针持续核对冻结身份/呈现策略、取消/interrupted 任务状态，正常 dispose 本身不再撤销已捕获投影的保存资格。
- 缺 JSON state 的旧投影从同一持久化 execution_records 任务行读取实际状态；必须是已知枚举状态且不是 cancelled/interrupted。完整任务仍走标准 router 的终态谓词。缺任务/未知状态仍拒绝。第一版因缺 state JSON 拒绝四个既有恢复/返回正例，已修复实现，未修改旧断言。
- controller.flush 的入口拒绝 disposed 后新捕获；销毁前已排队投影继续在保存前核对实时宿主探针。没有删掉 SN5 排队保存 guard，取消/身份变更的保存负例保留；旧 UI 操作仍由 disposed 检查拒绝。

四个 inverse mutations（每个 2 pass / 1 fail、exit1），已逐字恢复：恢复 !allowsPresentation 探针 → 正常 detach 的 step 不保存；忽略真实取消 → 撤销后字节被改；忽略冻结身份 → 新身份后字节被改；移除 flush disposed 入口拒绝 → 保留 flush 回调可在销毁后重新捕获新 scrollOffset，字节被改。原始日志仅 /tmp/sn5-detach-mutation-*.log。

恢复后 focused 80/0/0，包含 detach、新/旧 I4 负例、真实 JSON/native I5、M1、既有 resume/router、SQLite 恢复与返回正例。重新严格八包 analyze 全部零 issue/exit0。module_api 再跑 198/0/0/exit0；UI 再跑 385/152/0/exit0。host 新全量仍执行中，后续以真实摘要为准。host 命令使用仓库 scripts/ci.sh 原有 --timeout 120s 参数，不修改任何测试超时/断言、不把超时退出当通过。

旧 b489 宿主全量后来记录 1833 pass / 3 skip / 2 fail（仍无完整终态）：原 aiui6_stream_approval_widget_test 的 automatic true 发生其原定 10 分钟 TimeoutException，automatic false 为随后 TestFailure。全部其他测试推进后旧进程仍未结束，补修验证前停止旧进程；不当成新 SHA 的全量结果。SN6 仍由独立任务处理，本补修未修改其文件，也未合入任何外部实现。

本补修继续只在独立 SN5 分支交付，新最终 SHA / CI actual checkout 必须重新核验，不能沿用 b489 的 CI。未与 develop / SN6 组合，未自行合入。保留原任务和全部先前实施/失败历史。

发布补记：恢复后的云端命令行 git 缺认证，普通 push 失败，未冒称 1f863640 已推。改用已连接 GitHub git-object API 发布 RED→修复链；RED tree a5060d4019fec7441d712f7d717938c40e89c436 与原本地 RED 精确一致，更新独立分支采用 expected SHA、force=false。最终 commit 因连接器记录 author/committer 而与原本地 1f863640 不同，产品代码未改变；以 PR head / 远端 ref 核验的新 SHA 为准。原本地提交留存，不强推、不写原 owner 分支。

## Additional database queue boundary: RED only

On published head `eeea2c885d14fbec201bb1f6bfa702a87b4bd8ed`, the real native detach fixture now holds `ManagedConnection.exclusiveAsync` with a Completer, lets an event-loop turn submit the controller checkpoint save, synchronously replaces the agent planning identity, then releases the database queue. Result: 3 passed / 1 behavioral failure; expected the original projection bytes (revision 1), observed the detached old projection (revision 2, step `last native view`, scroll 321). The ordinary detach positive and both prior cancellation/identity negatives still passed. Raw output remains `/tmp/sn5-db-queue-red.log`; an initial fixture compile error was corrected and is not counted as behavioral RED.

This is a pre-existing second queue boundary in the host store, not introduced by the detach repair, and does not establish business execution escalation. Proposed minimal scope, reported before production edits: optional synchronous live eligibility callback on `HostUiWorkspaceStore`, supplied by `DynamicWorkspaceSession`, evaluated inside the save transaction immediately before INSERT. No changes to shared `UiWorkspaceStore`, `ManagedConnection`, personal-agent cancellation, SN6 or WC files. Production implementation awaits coordination of this additional host-store boundary.

Existing complete host run and remote CI remain running; no duplicate full host run or CI cancellation was requested. Previous b489 host run had two failures in the unchanged `aiui6_stream_approval_widget_test.dart` (blob `2fdd49bcd024e47227a7315a68c997c03ca141f1`, identical to PR51 d5cd): automatic true timed out after 10 minutes; automatic false raised `Reentrant call to runAsync() denied` at test line 21. These are not passing host gates.
