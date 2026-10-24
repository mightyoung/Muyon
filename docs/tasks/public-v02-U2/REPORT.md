# U2：云端纯状态 / 事件候选

2026-10-24。仅执行父任务已明确移交的纯状态 / 事件片，不是 U2 十族视觉组件、Shell 接入或 U3 验收完成。

## 固定基线与防重复

- 重新fetch develop=`e16af808620488a7be0b3b4a10b91190d18f1177`，未使用根工作树旧main。隔离树 `/workspace/muyon-publicui-u2`，分支 `task/publicui-u2-state-events-20261024`；未发现AGENTS.md。
- 读取完整原始计划 `64900d4a6a46a9ef2919bcf922fb059413b1ce82` 的 intelligent-ui，核其与当前develop相同；原设计 / 总索引与本次父任务限定共同适用。父任务确认另一云端U2已停且无改动 / 推送，唯一实施权转本线。
- 远端 `git ls-remote --heads origin '*publicui*' '*u2*' '*intelligent*'` 未见U2；GitHub PR搜索 `repo:mightyoung/Muyon U2` 及branch搜索无结果。当前树没有PresentationState/EventProjection，不复制他人未审候选。
- 仅读取当前已合U1实际模型 / codec / ValidatedPlan / 原报告，保留现有不可变计划与fail-closed规则，没有改U1生产文件。

## 实施范围与语义

新增 `product/ui/publicservices/PresentationState.kt`、`EventProjection.kt`、对应 `PresentationStateChecks.kt`；仅修改既有同目录 `run-offline.sh`，使同一入口先运行原U1再运行U2。没有修改Shell、MainActivity、ProductService、FFI、cards、foundation、Rust公共入口、原PR108或workflow；不与B1 Rust登记冲突。

保持计划精确UiState / BusinessSnapshot / PresentationAccess / UiEvent / EventPayload / UiEventOutcome声明。UiState输入是调用者拥有的data class；`projectPresentation`把其map与BusinessSnapshot的source list复制成不可变集合，复用原ValidatedPlan。投影可显示时保持原答引用、未存草稿引用、未知进度、原意图引用及来源关系相互独立，不合并成一个“成功”状态。

`projectPresentation` 是新增的纯读取投影入口：输入ValidatedPlan、当前UiState、BusinessSnapshot与宿主当前PresentationAccess；输出 `PresentationProjection(plan?,state?,snapshot?,domainActionsEnabled)`。read无效 / scopeGeneration不等 / state或snapshot过期 / 未绑定source时，返回三个null与false，清掉**本次返回**的受限显示数据；不会改写调用者持有的历史对象或擦除其他缓存。UI实际隐藏、订阅释放仍由后续Shell / renderer owner实现。action撤权保留可读数据和本地编辑，仅使Domain动作提示false。后来的access=true不能提升原ValidatedPlan验证时没有的action权限。

`projectEvent` 是纯admission projection：LocalView→AppliedLocal；DraftEdit→DraftUpdated；DomainRequest→RequiresConfirmation，永不返回Accepted。它不实际写入view/draft、不增长uiStateRevision、不记录seen ID、不保存、不网络、不订阅、不取消原意图。event去重集及编辑CAS仍须未来宿主按同surface和revision维护，不能把本地Duplicate当持久幂等证明。没有注入不连接的fake来虚构host调用=0；静态API没有host/command/engine port。

## 本片裁定与代价

- Ruling：未获准外观Renderer/Cards，U0仍draft，本片只做纯投影——代价是没有真实页面、订阅生命周期或TalkBack验收，不能以16组JVM检查代替U2视觉完成。
- Ruling：计划没有独立LocalView key目录，本片要求View.key等于该节点已声明LocalView绑定的actionRef；DraftEdit首片只接Form已声明fieldId且draftRef等于当前state.draftStateRef。不猜Choice编辑协议——代价是未声明key和其他编辑族暂Rejected，未来catalog须显式扩展，不得把此保守子集当完整组件交互规范。
- Ruling：只检查Edit值的Unicode/UTF8边界，不提前执行Money/Quantity或领域校验，允许decimal字段局部半成品`1.`——代价是DraftUpdated仅表示准入结果，保存/提交前领域owner仍须校验，不代表草稿已保存或业务成功。
- Ruling：优先当前read/scope，再核envelope/surface/node，再比较精确revision，之后核binding/payload/action权限，最后查合法事件的known replay。错节点 / payload的replay不会绕过为Duplicate；有效旧版本返回Stale——代价是重复且撤权的事件返回Rejected，消费者必须接受此保守优先级，不从outcome推断授权或重放安全。
- Ruling：局部state采用与U1工程候选相同的256 entries / 65536文本UTF8字节预算，值和事件载荷严格Unicode；此为本片fail-closed工程界限，不是视觉token或生产配额——代价是超限state隐藏 / event拒绝，未来配额必须另审。
- Ruling：BusinessSnapshot只核当前snapshot ref及来源属于验证时host source集合；SourceBinding与quote长度不证明quote逐字等于正文、来源未过期或当前授权——代价是后续宿主须重验真实来源，不能把投影存在当业务事实或来源可信证据。

原U1 Confirmation、非空Receipt.receiptRef、非空Attachment.stageCoverageRefs、非unsaved Draft继续TextOnly；本片不增加unchecked ValidatedPlan factory。Accepted类型为原计划保留的未来可信宿主结果表示，纯事件函数没有构造它的路径，也不能把任意Kotlin构造的Outcome视为授权。

## 实际TDD与回归

工具原环境实测Kotlin2.2.20 / Java21.0.12.1；固定org.json20250517摘要仍为 `3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`。无下载 / 安装 / 系统修改。现有runner保留 `-Werror -jvm-target17`、固定C1原fixture SHA及原38组，不另造C1事实。

命令：`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices/run-offline.sh`。

| 固定源 / 阶段 | 实际结果 |
| --- | --- |
| `56bd06e5a5821b42db5c0c3b22e4e41bb040dc29`，可编译Unavailable纯投影桩 | exit1；U1 38/0，U2 6通过/8失败。LocalView、Edit、RequiresConfirmation、Stale、Duplicate、可读投影 / 复制等正向行为真实失败，不是符号缺失 |
| 最小实现首轮 | exit0；U1 38/0，U2 14/0 |
| `4223bfbf28d68e2fa314bb156a064b025d93009f`，补原读权限不可提升与state边界两组验收 | exit0；U1 38/0，U2 16/0。两组为补充边界检查，不冒称有独立新增RED |
| 原cards入口 | `KOTLINC=/workspace/publicui-tools/kotlin-2.2.20/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh` → exit0，45 checks |
| 项目Android入口 | `cd apps/muyon_android && bash gradlew --offline --no-daemon :app:compileDebugUnitTestKotlin :app:testDebugUnitTest` → exit2，缺已有Gradle8.13，未进入编译 / 测试，NOT_RUN |

覆盖：精确大revision、有效replay、错误identity/surface/node、kind/payload错配、非法action/key/draft/field、partial edit、UTF8文本上下界、read/scope撤权、action撤权、初始权限不可提升、可变输入事后修改不影响已返回投影、只读集合、来源 / snapshot错绑、U1可信ref门槛、无状态写入 / Accepted。计数为检查组，不是设备场景。

## CI与Draft PR边界

读取现有 `.github/workflows/android-compile-only.yml`：只有push的三指定候选分支和develop，无workflow_dispatch，不含本新分支。现有完整产品PR workflow会准备模型资产 / SDK / native；本任务仅允许既有授权compile-only CI，不能为凑绿灯触发更大模型流程。因此提交保留 `[skip ci]`，不修改原CI owner的workflow、不绕过工程gate。候选准备后创建自己的Draft PR并核远端head / workflow状态；CI编译必须等已有CI owner登记本分支或提供现成精确源入口，未运行不能填PASS。

待CI action=`在现有compile-only入口验证本候选精确源`，target=`task/publicui-u2-state-events-20261024`，reason=原workflow不监听本分支且无dispatch，本环境缺Gradle，outcome=待CI入口交接、未运行、非审批拒绝。Android / 设备 / Renderer / 真实来源 / 真实模型 / 授权 / 保存 / 取消均未在本片执行。没有Mac或其他任务私有目录访问、main/develop合入、强推、删分支或部署。

## 仓库外日志

`/tmp/publicui-u2-evidence/`，不提交原始日志。

| 日志 | SHA256 |
| --- | --- |
| red.log | `bc4d6aa143a1d443968f21bea8daa4b3d3e4d446ea52cd09b4b79bd2274a87dd` |
| green.log | `baa075fa974b2c51d0cdd3eeb89c2516cd76a570edfb16831f9987b4326974ee` |
| final.log | `8b5962e74ebdaede4ad0aae4e6e825ebf5f28396206d96083a358de324f842ba` |
| cards.log | `7c4fdd18b1886ed9eafaf14138f7ec36a26a7758ed3d51f6b1923ee8e2fac02c` |
| gradle.log | `b7512eb8fcf1348379f75c4f42cba6eb1689934c3e287aa6aa364de19db1ef0f` |

## 独立审查

非作者 `/root/review_u2_state` 对固定 `e16af808620488a7be0b3b4a10b91190d18f1177` → `4223bfbf28d68e2fa314bb156a064b025d93009f` 四文件整片审查：Critical0 / Important0 / Minor0，可交B纯state/event候选，不代表完整U2或自动合入。独立实际执行：publicservices exit0，U138/0、U216/0；cards exit0 /45 checks；固定artifact / C1摘要均OK；固定范围diff-check通过。正式Gradle compileDebugKotlin / compileDebugUnitTestKotlin exit2 NOT_RUN，无安装。独审未改工作树 / index / HEAD，未派生子代理；没有必修项或待后置Minor。

审查 Declined to judge 裁定（与上述范围相同，不丢弃未验项）：

- Ruling：Android与云端CI尚未验证本SHA，保留NOT_RUN，交既有CI owner登记精确源入口——代价是仍可能有平台集成问题，不能以纯JVM通过补填Android。
- Ruling：Renderer/Cards视觉、页面接线、订阅释放、设备/TalkBack不属本纯投影片，保留原U0/U3 gate——代价是返回空投影不证明真实页面已隐藏或订阅已释放。
- Ruling：实际编辑/保存/持久去重/宿主调度授权不由本片承接，事件outcome不是效果回执——代价是消费者仍需原owner的CAS、权限与原意图链，不能直接执行RequiresConfirmation。
- Ruling：真实源解析、quote逐字一致性、覆盖可信性维持宿主工程gate——代价是本snapshot成员检查不提供原文真实性保证。
- Ruling：LocalView完整catalogue、Choice编辑及生产配额未冻结，保持本片保守key/field/预算——代价是未声明交互暂不可用，扩展前必须补精确合同与测试。

没有修改后再冒充原独审适用新产品代码；后续提交仅补本文证据，不触碰已审四文件。
