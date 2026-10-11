# SN-4：真实 InquiryUiPlanningSource 取消时保留合法只读退路

执行：grok-build。派发：leader A，2026-10-11。基线：`task/pr42-sn2-sn3-repair-20261011` @ `b6e185611a81853c99548d4528cd91cc8be36172`（AIUI 原作者交接点，见 `PR42-SN2-SN3-REPAIR.md`）。

## 问题（交接方指出，未证实）
`apps/muyon/lib/platform/inquiry_ui_planning_source.dart` 的 `read()` 在任务状态为 failed/cancelled/interrupted、或 await 期间权限修订变化时返回 null。PR42 的取消路径会再读一次真实 source；若此时返回 null 被当成「来源不可用」，可能把已校验、合法的**只读预览/宿主事实退路**一起清掉。现有取消测试用的是受控假 source，没覆盖真实 source。

## 要做
1. **先写会失败的测试**（真实 `InquiryUiPlanningSource` + 真实 SQLite 宿主，不用假 source）：
   - 选中询价对象 → automatic 规划流式进行中 → 取消规划；断言：原回答保留、只读预览/宿主事实退路仍在、执行能力为 0、零回调零工具。
   - 对照：取消期间真实撤权（scopeAuthorityRevision 变化或会话 scope 变化）→ 退路**应**被清掉。
   - 先推测试提交，CI 或本机跑出真实 RED，回报失败第一行。若测试直接通过，停下回报（说明问题不存在），不要改源码。
2. 最小修复：区分「规划被取消」与「来源真实失效」。取消只撤执行能力，不清退路；撤权、scope 变化、对象失效仍清。不放宽 failed/interrupted 等其他判断，不改 OC-11 未知事实拒绝。
3. 变异：至少两处（取消也清退路；撤权不清退路），都要被测试抓到。

## 约束
- 只在 `task/sn-4-real-source-cancel-fallback` 上提交推送；不合 develop，不碰原 PR42 分支和交接分支。
- 不删减、不放宽已有断言；`flutter analyze` 严格零 info；不提交 pub get 改动的 xcconfig/Podfile/analysis_options。
- 不跑真实模型，不读不打印 `.env`。

## 回报（固定 6 行）
1. 测试提交哈希与 RED 第一行
2. 修复提交哈希（远端与本地一致）
3. 改动文件与行数
4. 两处变异结果
5. analyze 与 apps/muyon 全量测试结果（pass/skip/fail）
6. 未做或有疑问的地方
