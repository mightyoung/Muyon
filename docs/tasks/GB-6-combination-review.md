# GB-6 最新 develop 组合复核

日期：2026-10-11。执行：Codex；只读交叉核实按 `REVIEW.md` 派独立代理。父会话统一决定合入；本分支不合入 develop/main。

## 固定输入与范围

- 首轮验证 develop：`56a7d8a898a9cf528f64b24f69c91d6cf44a5b2e`。
- GB-6 源：`task/gb-6-dispatch-turn-characterization-rest` @ `fc0ab40b639d7d7b066a4f3cd6caef650d74fac7`。
- 源 CI：[38111230154](https://github.com/mightyoung/Muyon/actions/runs/38111230154)，实际查询 completed/success，headSha 与源完全一致。
- 隔离组合分支：`review/gb-6-develop-combination-20261011`。
- 组合代码 SHA：`e25c474e62806c4cc5794199d6d0faaef116b31a`，双亲依次是上述 develop、源 SHA，ort 无冲突。
- 组合代码相对 develop 只增加两个 GB-6 测试文件（660、592 行）和任务文档（16 行）。本审查追加此摘要；无 `lib/`、既有测试、HK-4、工作流或门禁改动。
- 已读取 GB-6/GB-4、通用 REVIEW、ADR-0001～0005 及 CR-9 独立审查。仓库没有 AGENTS.md 或 `.agents`/本地 skills 指令；环境 `/workspace/.agents` 为空。当前用户授权覆盖旧 ADR 的云端执行限制，但不授予合入、部署、凭证或权限扩大。

## 交付逐项核对

下表 D、M 分别指 `apps/muyon/test/gb6_dispatch_characterization_test.dart`、`gb6_model_turn_characterization_test.dart`。这些用例使用真实宿主/注册器/仓库和 loopback 模型夹具，不能作为真实模型或设备证据。

| 项目 | 状态及依据 | 保留的边界 |
|---|---|---|
| G6 准备异常/关闭 | 部分满足；D:47、87 精确固定文案及 interrupted 终态；关闭先启动再释放，无旧等待环 | 未新增执行期错误文案/脱敏对照 |
| G7 destination | 主要目标满足；D:140 真实非法 URI formatter 与合法 prepare 的逐层持久化字段脱敏 | 非法 URI 不冒称经过合法外传 prepare；port/fragment 未独立钉住 |
| G8 digest/preview | 部分满足；D:211 多调用 digest、单调用 identity、两种 preview、选择后原 digest 仍可确认且只执行所选 | 未直接钉 `_stage(state:running)` 的 selection 字段条件 |
| G9 自动批准 | 主要目标满足；D:276 真实 grant 来源/id/uses/业务修改；D:456 合法 prepare→确认卡→running 后直接执行 automatic 防御边界 | authority 与 intent 同时为空的联合防御已覆盖；不冒称分别穷尽所有组合 |
| G9 撤销 grant | 补充行为覆盖；D:367 reviewer 暂停后撤销，业务不修改且任务非成功 | 单删 null guard 仍被后续 `approval!` 阻挡，不算该行的检出 |
| G10 mark 后 abandoned | 满足；D:548 approval commit 安排 microtask 改任务状态，断言无 effects、receipt、tool_result、假 failed/succeeded outcome | 模拟任务状态变化；不冒称真实 close/token 路径完全覆盖 |
| G11 人工/wire/block | 部分满足；M:61 普通确认诚实改名；M:87 真实 400 变体重审、待确认且无第二次发送，确认后第二次发送；M:153 初次 block | 未新增 FixedFailure/其他异常文案与脱敏 |
| G12 planning/profile | 所列两个场景满足；M:179、200 要求具体错误码和无发送 | 不代表新增 memory/scope 变化覆盖 |
| G13 output cap | preview 契约满足；M:241 正 room 与 streaming-only/native-only 对照 | 未验证最终发送体里的 cap |
| 首流事件公告 | 满足；M:341 已确认且服务器收到请求、首事件未发前无公告，释放后恰一条 | loopback/SSE 夹具 |
| native/compat 引用 | 满足；M:398 native 保留正文且去坏引用；compat 必须具体 Invalid citations，无 summary | 不是仅要求 failed 的弱断言 |
| G14 | 部分测试保留，整体延后；M:453、491、521、548 钉 120 边界、not_approved 文案、prior_failed 状态、resume 文案 | 其余键全集及 unknown_before_resume 措辞未完成，不称 G14 全覆盖 |

测试无空断言、sleep 或外网模型依赖；暂停用 Completer，失败清理释放暂停点。G10 依赖明确 microtask 边界，已以删 post-mark 守卫的动态变异确认实际触达。

## 动态验证与变异

SDK 为临时下载的 Flutter 3.47.5 / Dart 3.13.4，与 CI 版本一致；工具缓存定向临时目录。初次运行因只读用户目录导致 SDK hook 初始化失败，调整缓存后重跑成功；失败不计入测试结果。Flutter pub get 自动改动的三个 analysis_options 文件已恢复，没有提交。

命令与摘要如下。原始 analyze/test/mutation 输出只存临时目录，不入库；运行未设置真实模型评估变量。

每个变异只改变一个生产行为，在组合工作区临时执行后恢复；原实现 20 测试先通过，恢复后再完整重跑。只有退出 1 且出现目标断言的 Expected/Actual 才算检出，编译失败和超时不计。G9 删除三行自动保护后实际 effects=1，Expected=0，与用户负例独立一致；保留该测试。

- 新增两文件：`flutter test --no-pub --reporter expanded --timeout 120s test/gb6_dispatch_characterization_test.dart test/gb6_model_turn_characterization_test.dart`，初跑与全部变异恢复后均 `+20: All tests passed!`，退出 0。
- 单一变异 22 项：21 项目标断言失败检出（退出 1），1 项存活（退出 0）；无编译失败、无超时。测试名可按 `flutter test --no-pub --reporter expanded --timeout 30s <对应测试文件> --plain-name <测试名>` 独立复现。下表列出的生产变异均未保留在提交里。

| 单一变异（相对固定组合代码的行号） | 目标测试名 | 实测 |
|---|---|---|
| dispatch:177 校验文案改执行期文案 | `prepare_exception_uses_check_failure_message` | 断言检出 |
| dispatch:42 非法 destination 原样返回 | `invalid_destination_formatter_and_legal_prepare_snapshot` | 断言检出 |
| dispatch:232–234 多调用 digest 加 selection | `selection_change_does_not_change_tool_card_digest` | 断言检出 |
| dispatch:231 单调用 identity 换成错误 digest | `selection_change_does_not_change_tool_card_digest` | 断言检出 |
| dispatch:247 不写 waitingConfirmation selection | `selection_change_does_not_change_tool_card_digest` | 断言检出 |
| dispatch:705 sign → confirm | `automatic_grant_write_consumes_grant` | 断言检出 |
| dispatch:709–711 删除 automatic 拒绝三行 | `automatic_without_authorization_rejects` | 断言检出 |
| dispatch:707 单删 null approval 守卫 | `automatic_sign_null_after_revoke_fails_closed` | 存活，不计检出 |
| dispatch:495–498 删除 mark 后状态检查 | `invoke_abandoned_after_external_mark_without_receipt` | 断言检出 |
| model_turn:167–170 删除初次 block 处理 | `model_content_block_fails_with_fixed_reason` | 断言检出 |
| model_turn:182 wire-required 误处理为 failed | `wire_review_required_holds_variant_without_second_send` | 断言检出 |
| model_turn:223–226 删除 planning 保护 | `planning_session_expired_before_send` | 断言检出 |
| model_turn:259–260 删除 profile 比对 | `check_permission_task_detects_profile_change_mid_prepare` | 断言检出 |
| model_turn:581–583 删除 cap capability early return | `nonstreaming_compat_preview_omits_max_output_tokens` | 断言检出 |
| model_turn:581 && → || | `nonstreaming_compat_preview_omits_max_output_tokens` | 断言检出 |
| model_turn:508–516 公告移到首事件之前 | `drain_announces_model_request_only_after_first_stream_event` | 断言检出 |
| model_turn:809 native 保留坏引用 | `native_bad_citation_strips_but_compat_bad_citation_fails` | 断言检出 |
| model_turn:387–395 删除显式引用校验 | `native_bad_citation_strips_but_compat_bad_citation_fails` | 断言检出 |
| dispatch:936 >120 → >=120 | `log_entry_truncates_above_120_chars` | 断言检出 |
| dispatch:65 not_approved 文案改变 | `not_approved_not_run_text_is_fixed` | 断言检出 |
| dispatch:654 prior_failed 状态改 not_approved | `not_run_prior_failed_status_key_is_fixed` | 断言检出 |
| dispatch:71 resume 文案改变 | `not_run_resume_text_is_fixed` | 断言检出 |

- 离线脚本：门禁 10、doctor 23 scenarios、coverage check 9、DA details 5、Laya 四组 8/4/8/9，均通过。
- 八个包 `flutter analyze --no-pub` 独立重跑全部 No issues found，退出 0。首次全仓脚本的 analyze 阶段因 `.dartServer` 写只读用户目录退出，采用 `ANALYZER_STATE_LOCATION_OVERRIDE` 指向临时目录后逐包复核通过；不把初次脚本写成全仓成功。
- 全仓测试/覆盖门槛继续由未改动的 `scripts/ci.sh` 及分支 push 触发的 `ci` 执行。最终完整结果、run URL 和最终 HEAD SHA 由本次交付回报提供；只有 headSha 匹配且 completed/success 才满足组合 CI 门禁。Linux 自跳过计数按实际套件摘要记录，不计作已覆盖，不推断全部跳过原因。
- 本摘要为纯文档追加，代码组合 SHA 上的 20 测试、22 变异与八包分析结果同样适用于含该摘要的最终候选；产品和测试内容没有再次修改。

## 可合判断

没有阻断性代码/测试发现，**建议作为测试增量合入候选**，前提是父会话复核最终候选对应完整组合 CI 为 success。未合入 develop/main。源分支已有成功 CI 只确认源，不替代本组合验证。

独立代理先静态逐项检查，后只读复核变异脚本、摘要 JSON 与恢复日志：确认 22 唯一变异、21 目标断言失败、1 存活，原实现及恢复后均 20 通过，当前 lib 差异为空。独立代理未重跑 Flutter；本报告动态执行结果来自主执行线程，不冒称两次独立全仓重跑。

G14 及表内缺口继续留待后续，不把此增量当作全部拆分门禁已满足。禁止把源 CI 代替组合 CI，父会话只在复核目标 SHA 与对应 CI 后决定合入。

## develop 前移后的再次组合

首轮最终候选 `2d4a446f725145f8197ba2ca8f9add43cc59b71c` 的 [CI 38114037829 第二次执行](https://github.com/mightyoung/Muyon/actions/runs/38114037829/attempts/2) 已 completed/success，headSha 精确匹配；八包分析通过、测试共 3304 通过 / 207 跳过，coverage 与完整 CI 门禁通过。第一次执行因既有 supplier_core LAN trickling-upload 用例的 150ms deadline 超时失败；同一 SHA 仅重跑失败 job 一次，本地隔离重跑该例通过。保留首次失败，不修改该测试或门槛。

本地完整脚本两轮均八包测试通过；首轮 analyzer 缓存目录不可写，修正目录后第二轮分析通过但覆盖门槛失败（module_api 2087 < 2091），首轮 2094、远端第一次 2093；覆盖采集波动的根因尚未确定，不把本地完整 gate 记为成功，也未降低基线。

最终复查 develop 前移到 `ece1a76cbec0d1814a6bf0f72adb7abfc9067936`（REG-3c，五个文件）；与 GB-6 四个文件无重叠。再次组合以该 develop 完整 tree 为基础，仅追加原 GB-6 两个测试、任务文档及本摘要，双亲为首轮最终候选与上述 develop；不混入其他产品改动。22 个变异的被测 dispatch/model_turn 实现未被该 develop 增量修改；新增基线仍需最终新 SHA 对应的完整组合 CI，最终交付将提供精确 SHA 和 run，首轮绿灯不替代再次组合门禁。
