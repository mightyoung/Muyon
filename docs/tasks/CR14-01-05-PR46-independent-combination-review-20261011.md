# PR46 / PR47 / PR48 新基线独立组合复验

日期：2026-10-11。授权：本轮先完成 OC13/OC14/CR10F3 唯一合入职责，再对 PR47/PR48 做组合候选；随后父线程转交 PR46 最新补强关闭 I1 的独审结果，明确将固定 PR46 加入三项组合。本批未获合入授权，不合入 develop/main。所有活动 writer 和分支保留。

## 基线与固定交付

上一批完整 review（含报告）已正常 no-ff 合入并推 develop：
`52250649d34b4983929daf815430a0c6789d16db`，父提交为
`2224c6faca32c28ebdaa148d741b1a618df87987` 与 `a2d32de412b0feb5d5649f64a36f418337955673`。
合入树与 a2d32de 完全一致，仅比已测代码 cd3bb02 新增报告。
合入后 [CI 38135684507](https://github.com/mightyoung/Muyon/actions/runs/38135684507)
headSha 精确为 52250649，completed/success，2026-10-11 11:44:41 UTC 完成；
8/8 analyze、8/8 suite、3410pass/207skip/0fail、coverage/Laya 成功。
报告提交 a2d32de 的 `[skip ci]` 没有自身 workflow/check/status；不把合入或代码 CI 冒称为该文档 SHA 的 CI。
main 保持 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`，无强推、删除或部署。

| 对象 | 完整 SHA |
|---|---|
| 本批固定 develop 基线 | `52250649d34b4983929daf815430a0c6789d16db` |
| PR47 / task/cr14-05-single-item-projection | `67454faaddd99c0afc6838a4158f9dac557e9fa4` |
| PR48 / task/cr14-01-fact-notifications | `3d8e87daae9532da3f912e7fbe58e3e1e11ea82b` |
| PR46 / task/ci-prose-assertion-boundary | `e370a5e82e5b2da233310600b493d33872d8b02a` |
| 最终三项组合代码候选 | `734c764ca92a2e39831ac17079c5a65f5f670eca` |

独立 worktree；分支 `review/cr14-01-05-independent-20261011`。
顺序正常 no-ff 合入三条固定作者分支，保留 RED 前置测试提交，不只摘最后实现。
组合中间提交 `7620e673bfff2aee0a715a1bfe12f3d658c0df4f`、两项代码候选
`18e8585da3c9cf41d1379c6be19c46d4e944c07b`，最终三项候选为表中 SHA。
开工源 SHA、PR headRefOid 与父线程固定交付一致；三 PR 均 draft、autoMergeRequest 为 null。
无冲突，相对基线 11 文件、1171 additions / 11 deletions；各交付文件逐字与各固定源一致。
作者分支、develop、main 未因本批复验修改。

已读 CR14-01/05 任务、CR-14 F1/F2 设计、REVIEW、不变量与相关 ADR（沿用上批读取），
并逐行检查新增投影/声明、通知差异、通知/投影/源码变异测试。
固定源未找到 AGENTS.md/.agents/skills，工作区规则同上批。
父线程已转交 PR47/48 最终独审 C0/I0/M1 及 PR46 补强后关闭 I1 的最终独审；下列 M1 如实保留，不改固定交付。

## 范围结论与后续建议账本

| 交付 | 本次结论 |
|---|---|
| PR47 单项投影 | 稳定对象+操作 itemId，operationKeyRef 绑定父任务/呈现/尝试/完整 pin/草稿修订/旧新值；单项 snapshot/context/record refs 隔离，旧值 verified、新值 unverified；数量映射与真实 set_item_qty 参数规则一致。 |
| PR47 拒绝边界 | 未声明、重复声明、不完整生命周期、atomic、未知映射、重复目标操作、未 pin 和非法数量拒绝整批；嵌套宿主输入冻结、重排与 map 键顺序稳定。 |
| PR47 能力边界 | 纯投影，无 router/UI/DB 写入口，未注册模型动作；字符串身份与 pin 的投影冻结不等于真实执行资格验证。CR14-06/07 仍须后续依赖、恢复和逐项真实回执证明，不称 F2 已关闭。 |
| PR48 真实通知 | 同一 ManagedDatabase 共享同步通道；task/source 锁存后、入队前发布，事务方法在进入事务后、落盘前发布；写库 ABORT 后保持通知/锁存；重复来源去重、不同 DB 隔离、dispose 仅解绑自身订阅。 |
| PR48 受限变更 | 未改 OC-11 readTask 规则、授权/审批/账本、storage onCommit、router、INSERT guard、UI 或 CR14-02 单调失效序号/故障恢复；正常路径提前通知与 readTask 惰性锁存正确。 |
| PR46 全 payload 拒绝文本守卫 | 仅改 streaming 测试；固定 UUID 重现元数据碰撞，同时保留 task messages、真实下一轮模型 messages、summary 2080 与完整 `_prose` 的全 payload 守卫。覆盖补强关闭旧 I1，不把部分文本检查冒称完整载荷检查；不改产品代码。 |

| 建议 | 级别与边界 | 后续条件 |
|---|---|---|
| PR47 `single_item_operations.dart:8-11` independentPrepare/Commit/Receipt 默认 true、atomic 默认 false | M1，非阻断；当前唯一 set_item_qty 声明与真实 handler 一致，不能称现有漏洞 | 后续声明接口改显式 required 或默认拒绝；由相应 owner 单独变更与验证，不私改本次固定源。 |
| PR48 低层 createTask 可人工构造同会话异构 scope，早通知后跨任务锁存可能漏通知 | M1 防御边界，非生产阻断；正常 chatTask/toolTask 冻结 conversation.scope，UI 复用匹配会话，未确认正常可达路径 | 后续低层身份/范围强化与失效机制 owner 处理，配真正异构 scope 回归；不将此边界测试构造写成已发现生产漏洞。 |

## 本次本地复验

Linux / Flutter 3.47.5 / Dart 3.13.4；SDK bin 加入 PATH，源码变异子进程能真实启动 dart。
pub get 生成的三个 analysis_options 改动已恢复；初次测试加载因新 worktree 尚无原生缓存失败，
复用同版本官方 hook 下载的 PDFium/SQLite 资产后重跑。环境失败不算行为失败。
未导出 MUYON_EVAL_REAL，不跑真实模型、Android 或部署；原始日志仅在 /tmp。

从 apps/muyon 运行 `flutter test --no-pub --reporter expanded`，目标文件：
host_authorization_notifications、assistant_authorization_facts、single_item_projection、
single_item_projection_mutation、inquiry_host_taint_probe、assistant_authorization_policy、
assistant_grant_integration、assistant_cancel、assistant_outbound_authorization、outbound_ledger，
三项组合另加 personal_agent_streaming（24 例）。
初始两项 GREEN/恢复 GREEN 均 129pass；最终三项首次 GREEN **153pass / 0skip / 0fail，exit 0**。
最终三项全部临时注入恢复后 GREEN 同为 **153pass / 0skip / 0fail，exit 0**。
其中真实通知 13 例、既有 facts 25 例、投影 11 例、投影源码变异 2 例；其余为宿主 probe、授权、取消、外传、账本回归。
宿主 `flutter analyze --no-pub --fatal-infos`：No issues found，exit 0。

PR47 两个真实源码变异本次独立重跑：baseline exit 0 / PASS；数组下标 itemId 与共享 operationKeyRef
均以 driver 行为断言失败 exit 65 / EXPECTED_ASSERTION_FAILURE 检出；编译/启动失败不算 kill，产品源码不改。

| PR48 临时单处逆变异 | 本次独立结果 |
|---|---|
| 取消 markExternal 发布 | exit 1，0pass/4fail；锁存先于落盘、失败保守、去重及已知来源新任务历史均检出。 |
| 取消 markSourceExternal 发布 | exit 1，3pass/3fail；source 即时通知、失败保守、去重检出。 |
| 取消 markSourceExternalInTransaction 发布 | exit 1，0pass/3fail；事务落盘前、失败保守、去重检出。 |
| markExternal 发布移到 write 成功之后 | exit 1，2pass/2fail；入队前即时通知与 ABORT 后通知检出。 |
| markSourceExternal 发布移到 write 成功之后 | exit 1，4pass/2fail；入队前即时通知与 ABORT 后通知检出。 |

五变异均测试实际行为断言失败，无 load/compiler failure；每次 finally 恢复原字节。
PR46 本次独立补验：仅临时改测试，真实请求完成后在 final task snapshot 用 `task.copy` 分别注入
`error: _prose` 与 `preview.messages` 的完整 `_prose`，两次均是新增全 payload 守卫的行为断言
0pass/1fail、exit 1，Expected not contains 完整 `_prose`；保留原 UUID、task messages、实际下轮和 summary 检查。
这是测试快照注入，不宣称生产发生错误字段/preview 泄露，不改领域或宿主产品代码。
两次均 finally 恢复测试原字节，作者自述的两次注入 RED 不冒称独审重跑，本次另有独立证据。
恢复后 `git diff HEAD -- apps packages docs scripts .github` 为空，报告写入前工作区干净，diff --check 通过。
作者原始 RED / 5mutation 自述不是独审重跑证据；本次上述命令提供新的独立 GREEN/变异证据。

## 精确远端证据与候选状态

PR47 [source CI 38134460939](https://github.com/mightyoung/Muyon/actions/runs/38134460939)
headSha 67454fa，completed/success；旧 [PR CI 38134463601](https://github.com/mightyoung/Muyon/actions/runs/38134463601)
元数据 headSha 是作者源，实际 checkout 经日志核对为 `f9ebb4297ddf2da741ef0725ce3bb279b66594f1`（67454fa 合 2224）。
PR48 [source CI 38134640353](https://github.com/mightyoung/Muyon/actions/runs/38134640353)
headSha 3d8e87，completed/success；旧 [PR CI 38134652874](https://github.com/mightyoung/Muyon/actions/runs/38134652874)
实际 checkout 为 `575d8305009febd4110f3a945b32ced3815a9808`（3d8e87 合 2224），已独立核对日志。
旧 PR CI 均不包含上批刚合入的三个交付，不代替本批组合门禁。

PR46 [source CI 38135738465](https://github.com/mightyoung/Muyon/actions/runs/38135738465)
headSha 精确 e370a5e，completed/success；[PR CI 38135741423](https://github.com/mightyoung/Muyon/actions/runs/38135741423)
实际 checkout 经日志核对为 `ba8530050563193b734fa375f0b7c7deb4a7c54c`（e370a5e 合本批基线 52250649），
completed/success。该 PR CI 不包含 PR47/48，仍须三项新组合。

初始两项 [CI 38136769834](https://github.com/mightyoung/Muyon/actions/runs/38136769834)
headSha `18e8585da3c9cf41d1379c6be19c46d4e944c07b`，终态 completed/cancelled；
因同 review 分支加入最新获审 PR46，workflow concurrency 自动取消旧 run，不能记 success。
最终三项 [CI 38137181768](https://github.com/mightyoung/Muyon/actions/runs/38137181768)
headSha 精确为 `734c764ca92a2e39831ac17079c5a65f5f670eca`。
**终态 completed/success**，job `114463389344`，2026-10-11 12:11:08 UTC 完成。
8/8 analyze、8/8 suite、verification gates、doctor 23 场景、coverage、Laya 均成功。

| 三项组合 CI 套件 | pass | skip | fail |
|---|---:|---:|---:|
| module_api | 250 | 0 | 0 |
| muyon_ui | 380 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 220 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 1732 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |

合计 **3436pass / 207skip / 0fail**；平台/字体/真实模型 skips 不算该能力验收。
CI 后 ls-remote：develop 仍为固定基线 52250649，三作者固定 SHA 均未变；main 未变。
本报告为纯文档，提交使用 `[skip ci]`，其自身没有 CI 终态，不能称自身 CI success；
本次成功门禁严格属于代码候选 `734c764ca92a2e39831ac17079c5a65f5f670eca`。

**候选满足本次三项有界组合验证条件，C0/I0 与两项 M1 建议保留。**
下一批合入仍等待统一 leader 明确授权；基线若移动，应重新组合验证。
通知机制不等于 CR14-02/03/04/08/09 已完成，纯投影不等于 CR14-06/07 真实执行/恢复已接通。
PR46 只修确定性测试误报与完整载荷守卫，不宣称改动模型生产行为。

本批只形成 review 候选，不 merge develop/main、不 forcepush/delete/deploy。
