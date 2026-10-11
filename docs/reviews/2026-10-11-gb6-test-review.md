# GB-6 特征测试独立审查（CR-9，ChatGPT 6 Pro）

审查对象：`task/gb-6-dispatch-turn-characterization-rest` @ `0a08689`，对照 GB-4 第 3、4 节 · 只读 GitHub，未运行测试或变异（「变异后失败 / 仍通过」均为推测）· 原稿由用户转交，leader A 整理入库，代码位置以原稿为准。注：执行者随后推了 `be6f15a`（「本机 Flutter 运行后修正」），本审查未覆盖该提交。

**结论：修改后合入。** 有值得保留的断言，但目前不能作为「G6～G14 已补齐」的拆分门禁：G6、G10 存在等待环；G7、G9 的夹具在目标分支之前就被生产校验挡住；G11 的 wire 用例、G13 的预算反例、首流事件用例没有约束它们声称约束的分支。

| 缺口 | 问题 | 要求 |
|---|---|---|
| G6 准备期 vs 执行期文案 | 测试在 `resolveScope` 暂停后先 `await agent.close()` 再释放；`close()` 等待活动 `startTool` → 确定等待环；且 `close()` 先把任务写成 `interrupted`（终态，`ctx.fail` 不能覆盖），与期待的 `failed` 冲突 | 拆开：普通 prepare 异常固定校验类文案（变异 `agent_dispatch.dart:177` 改成执行期文案应失败）；prepare 期间关闭保持正确关闭终态并完成清理；执行期异常用执行期文案与脱敏。不得允许 `failed` 覆盖 `interrupted` |
| G7 非法 destination | 直接辅助函数断言有价值；native 上卡场景把参数 destination 设为 `%`、transport intent endpoint 设为合法 URL，生产会因 `intent_mismatch` 拒绝 | 保留 formatter 测试；另构造能合法完成 prepare 的展示快照场景；持久化断言逐层解码检查具体字段，不对整份 `jsonEncode(payload)` 查子串；不得放宽 endpoint 身份校验 |
| G8 digest 与选择 | 多调用 digest 等值断言有效（变异：digest 输入加 selection IDs 应失败） | 补单调用 identity、single/multiple preview 形状、`_stage` waiting/running 字段差异；不要扩大成「运行中永不含 `toolSelection`」（`executeCard` 会记录本次选择） |
| G9 automatic 无 authority | 虚构 `test/row/r1` 对象与 `test` 模块，真实 `ScopeResolver` 先拒绝；`prepares` 计的是 effectIntent producer 调用次数（`isPureLocalWrite` 也调用）；intent 由非空变空会先触发 identity 不一致 | 分两条：`executeCard(automatic:true)` 无 authority / 无 intent 的防御边界（删 `agent_dispatch.dart:709-711` 的 throw 应失败）；有真实有效 grant 的自动执行，检查授权来源与 grant 消费（`sign` 改 `confirm` 应失败）。用明确阶段信号，不靠调用计数 |
| G10 mark 后 abandoned | 与 G6 同样的等待环（`close()` 等待已登记的 `confirm`）；暂停点在 `executeCard` prepare，关闭后会被 `_invokeOne` 入口检查挡住，测不到 mark 后的第二次检查；只禁止成功回执、允许假的 failed 回执；`startTool` 本来不会进下一次模型请求，`f.bodies` 为空没有判别力 | 证明已越过入口检查、在 external mark 的异步边界改变 closing/running；区分 token 取消与任务状态变化（`close()` 先取消 token，第 494 行先查 token）；断言没有新增 receipt、tool_result、失败 outcome；删 `agent_dispatch.dart:495-498` 才应失败；失败时也要释放暂停点 |
| G11 waitForModel | block 用例有效（删 `agent_model_turn.dart:167-170` 应失败）；wire 用例用的 `ConfirmModelReviewer` 只返回 confirm，走的是普通人工确认，不是 `HostModelWireReviewRequired` | 现 wire 用例改名为普通确认；另按 `assistant_production_model_protocol_test.dart` 的真实场景（自动权限、非流兼容请求收到 400、变体重审要求确认）补真 wire 用例，断言待审变体尚未发出第二次请求（不是总请求数为零）；补 `FixedFailure` 与其他异常的文案与脱敏 |
| G12 planning / profile | 两条都触达目标守卫；profile 用例接受「`model_source_changed` 或任何执行失败」，太宽 | 错误必须包含 `model_source_changed`；不能据此宣称 memory / scope 变化已覆盖 |
| G13 非流兼容不加 cap | 反例 prompt 估算已 ≥ 520 tokens、预算 500，`room <= 0` 本来就返回 null，删掉 capability early return 也照样通过 | 建立 `0 < 剩余预算 − 估算 < maxOutputTokens` 前提；补 streaming-only、native-only 对照（`&&` 改 `||` 应失败）；检查实际发送体。「输入估算已超预算仍进等待确认」是否合理另行确认，不在此固定 |
| G14 截断与文案 | 截断断言有效；`_notRunText` 8 个键只约束了 `not_approved` 完整文案、`not_run_prior_failed` 状态键、`not_run_resume` 子串；其余未覆盖；`prior_failed` 真实路径在写消息前就 fail 返回 | 补恰好 120 字边界（`>120` 改 `>=120`）；逐键新增文案测试；三个场景拆成独立测试；**`unknown_before_resume` 文案（「未执行：上一次尝试中该操作的结果未知」）与真实 hold 提示（「可能已经执行，但结果未知」）语义冲突，先确认措辞再固定** |
| 第 17 条 首流事件后公告 | 负向断言在 `confirm` 之前；夹具先写并 flush 第一段 SSE 再等 hold，暂停点晚于首事件；把公告移到 `await for` 之前测试仍通过；200×20ms 轮询约 4 秒窗口在慢 CI 可能误失败 | 增加「确认后、首个 ModelEvent 前」的暂停点：先断言无公告，再释放首事件，检查恰好一条；失败清理中保证释放 hold |
| 第 18 条 坏引用 | native 剥除断言有效但没检查正文保留；compat 删掉显式引用校验后 `all[98]` 越界照样 failed，测试仍过 | native 补正文「答案」仍在；compat 失败原因必须是 `Invalid citations` 或稳定专用错误码 |

## leader A 本机变异清单（推测，先确认原实现下目标用例通过，再逐条单一变异；超时、编译失败、无关前置错误不算检出）
文件前缀 `apps/muyon/lib/assistant/`。
- 现有有效断言应检出：`agent_dispatch.dart:232-234` digest 加 selection IDs；`agent_model_turn.dart:167-170` 删初次 block 处理；`agent_model_turn.dart:223-226` 删 planning 检查；`agent_model_turn.dart:259-260` 删 profile digest 比较；`agent_dispatch.dart:937` 截断改返回完整摘要；`agent_dispatch.dart:65` 改 `not_approved` 文案；`agent_dispatch.dart:654` `not_run_prior_failed` 状态改 `not_approved`；`agent_dispatch.dart:71` 改 `not_run_resume` 文案；`agent_model_turn.dart:510` `announced = true` 改 false；`agent_model_turn.dart:809` `return ''` 改 `return m[0]!`。
- 修夹具或补断言后必须检出：`agent_dispatch.dart:177`、`:42`、`:231`、`:709-711`、`:705`、`:495-498`、`:936`、`:66-70,72`；`agent_model_turn.dart:182-195`、`:267`、`:581-583`、`:581`（`&&`→`||`）、`:508-516`、`:387-395`、`:811`。
