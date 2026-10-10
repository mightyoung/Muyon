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

## 第三轮：F3a纯计算与F5a草案基础片

冻结基线 develop `0466f113fd7dd41f99c38cef11eca428622a6fac`，第二轮
[发布CI37971444082](https://github.com/mightyoung/Muyon/actions/runs/37971444082)
completed/success。候选仅以下两项，T-3/AIUI-4明确不纳入：

| 候选 | 完整SHA | 独立复审/精确源CI |
|---|---|---|
| F3a | `4943c6bbdac71080615c7fec811589025213db80` | [复审](AIUI-3-F3a-review.md)无确定阻断；[CI37980112557](https://github.com/mightyoung/Muyon/actions/runs/37980112557) success，host1314~3 |
| F5a | `f0203bf5030410f23e056bf8c6eeb6956c0593f2` | [复审](AIUI-5-F5a-review.md)无确定阻断；[CI37979546165](https://github.com/mightyoung/Muyon/actions/runs/37979546165) success，UI323~152 |

两项仅新增文件，无冲突。F3a为26计算行为+4源变异共30新增测试，不接runtime。
F5a仅草案/夹具归档，正式schema未采纳，stream/2与F5b/c必须另行决定；不以合入扩大权限。
精确组合CI成功后再重核develop并正常推送，继续追踪精确发布CI终态。

第三轮组合 `9c8ce33859ba8ba1d4f72ab249fd58dc3b8a1bfb` 的
[CI37981869411](https://github.com/mightyoung/Muyon/actions/runs/37981869411)
completed/success：analyze8/8、test8/8 suites、module_api68、muyon_ui323~152、host1314~3。
发布前再次fetch/ls-remote确认develop仍为0466f113完整基线、main未变。
收尾仅摘要和索引状态，产品/脚本/夹具树与已测组合一致。最终发布SHA与CI终态由执行回报核对。

## 第四轮候选：AIUI-4 暂缓于测试缺口

基线 `6e40a7956f2deb3ff53ee0397ae7cb4e1065c83d`；第三轮发布
[CI37983292909](https://github.com/mightyoung/Muyon/actions/runs/37983292909) success。
冻结 AIUI-4 `fc02783ad078fd0cd90f577bb7cfe129e22f19d9`，两位独立核实者复审
见[AIUI-4-review](AIUI-4-review.md)：取消竞态与恢复路径无确定阻断，source/定向CI成功，
但200%活动工作区正文与布局退路测试缺失，属任务书明确本轮应改。
本地正常合并无冲突，核与PR自动组合产品树一致后已撤销临时未提交merge；
尚未推本轮组合或develop，待原作者补测试/精确新SHA与CI后继续。T3/AIUI4-F4c不在授权范围。

第四轮补验冻结 `140068385a3b499c13b2ec24af4ed7c30e4f0a4c`，独立复审确认200%活动工作区
应改关闭；新增用例真实RED检出窄route回宽pane缺陷，最小viewport订阅修复后source全量
CI37991515411 success、定向37991523315 58/58。正常组合无冲突，准备运行精确组合门禁。
取消b411保持；F4c/stream2未授权，T3继续不纳入。本轮旧暂缓记录保留为历史。

第四轮精确组合 `d54e08a65754f029285838c9c6bde4f4d33e832a` 的
[CI37993094024](https://github.com/mightyoung/Muyon/actions/runs/37993094024) completed/success：
analyze8/8、test8/8、module_api68、UI323~152、host1347~3。发布前fetch/ls-remote重核
基线develop仍为6e40a795完整SHA，main未变；收尾仅复审历史措辞/索引/门禁摘要，
产品与脚本树不变。最终发布SHA与精确CI终态由执行回报核对。

## 第五轮：T-3 未注册handler基础片

基线 `c98c09274d4f903f5760f6c415801bd4be014c56`；第四轮发布
[CI37994429362](https://github.com/mightyoung/Muyon/actions/runs/37994429362) success。
冻结候选 `72dcb61a9a8e09995fd1e10f5c2c2bbde201b079`，3新增文件，两位独立复审通过，
[复审摘要](T-3-platform-read-tools-review.md)。精确push37995814951/PR37995821460均success，
host1366~3（+19）。只归档handler/隔离测试，bootstrap保持关闭、完整T-3未完成。
共享prepare的生命周期/条件恢复写入仍阻断生产接线，不扩大registry架构或创造只读授权例外。
正常组合无冲突，按精确组合CI成功→重核develop→正常发布→精确发布CI终态执行。

第五轮精确组合 `0e94827cb56165db2d03f825ff056b00340e24d8` 的
[CI37997331880](https://github.com/mightyoung/Muyon/actions/runs/37997331880) completed/success：
analyze8/8、test8/8、module_api68、UI323~152、host1366~3。发布前fetch/ls-remote重核
基线develop仍为c98c092完整SHA，main未变。本次收尾仅门禁摘要，产品与CI树不变。
最终发布SHA和精确CI终态由执行回报给出，bootstrap继续关闭、完整T-3仍未完成。

## 第六轮：PR14 T-3 metadata scope 机制片

冻结基线 `3b0adb9e5242dc4a598bf3be71a8252204a9a053`，最终源
`2f7cdee41a428bd02257de990e2e54242a01ddc1`，8文件限定机制/测试/文档。
[独立复审](T-3-metadata-scope-review.md)及真实Claude最终窄审通过，B1同host顺序缺口关闭。
最终源push38017057408/PR38017060942双绿已核实；本轮另主动推精确源到独立review分支，
[CI38018663166](https://github.com/mightyoung/Muyon/actions/runs/38018663166) completed/success：
analyze8/8、test8/8、supplier490/4skip、host1404/3skip、doctor23与Laya四组全通过。
没有混入LAN诊断分支或并行Harness分支，没有重试挑绿。

旧2cb独立run38016276386的LAN第二合法请求400保留为**未重现、原因未明**；
单次隔离诊断38017703913成功、合法请求200/空正文/客户端35.245ms，不冒称LAN已修复。
Claude交叉研判支持deadline优先候选，仍未确诊；先持久化消息ID再交付文件的基线重试窗口
另列后续待办，不因本片修改LAN。所有原始日志只存Actions或/tmp，不进仓库。

当前固定源全套门禁通过且无确定当前提交阻断，按用户“能合入的尽量先合入”授权合机制片，
不等其他未审PR。重核develop未变，正常no-ff merge审查远端精确源，无冲突、合并后与
源树逐字一致；收尾仅复审摘要/索引/本交接，不改变已测产品/测试/CI树。
生产bootstrap仍OFF，完整T-3及设备/真实模型/Mac golden验收不宣称完成。
最终develop完整SHA、ls-remote与精确发布CI终态由执行回报核实。

## 第七轮：PR15追补与PR16独立整合

PR14发布b8a9a52的CI38019480351终态cancelled，不报成功。GitHub API确认PR15由
账号mightyoung于2026-10-10T03:15:14Z合入cf672164e4f6c3e7beea8029c8be735e33c3bf19，
不是本线程执行；仅记账号/时间，不推断会话责任。[PR15追补复审](HARNESS-DREAM-CONSISTENCY-review.md)
无当前确定阻断，组合CI38019908442 completed/success，analyze/test8/8、host1429/3skip、
doctor23与Laya全通过；25新增行为测试仅8例取得先行RED。历史取消日志不入库。

PR16冻结源147ad71378af7ae7206b1e2c6ca2d76f98fc0639，真实Claude四窄包完整通过，
[独立复审](HARNESS-RESUME-IDENTITY-review.md)核机制与30新增行为测试无当前确定阻断。
源push38019568121/PR38019570449双绿，但后者实际只覆盖source into b8a9a52，不含Dream。
本线程据最新cf672正常组合b70d377d138ec3631b64a3f0ec4072823779f015并主动推review，
[独立CI38020976416](https://github.com/mightyoung/Muyon/actions/runs/38020976416) completed/success。

复审期间API确认PR16由账号mightyoung于03:34:35Z已合入
38f2040bbdb7b7d0f766891c94c3440d208a7f6c，也不是本线程执行，不重复合入。
其整树与独立组合b70d377逐字一致，[发布CI38021050451](https://github.com/mightyoung/Muyon/actions/runs/38021050451)
completed/success。两项均analyze/test8/8、host1459/3skip、supplier490/4skip、doctor23、
Laya8/4/8/9全通过，无重试挑绿。本线程随后仅正常ff当前已合基线并提交必要审查摘要/索引/交接，
产品、测试、CI树与已验组合一致。摘要收尾发布完整SHA/ls-remote/对应CI终态另在执行回报核实。

工具进展恢复预算与检查点按任务验收通过；无工具进展的纯模型任务仍可能走fresh，
不称所有恢复连续。摘要比较不是任意本地数据篡改认证，同进程故障夹具不称进程重开取证。
LAN400仍“未重现、原因未明”，独立LAN任务继续；PR18未来夹具/契约冻结不随此合入。

### PR16合后新P1更新（不是CI失败或已修复结论）

03:37:36Z机器人review5477387202对精确源147ad713报manual hold再次pause/resume丢历史
invocationId/digest、可能转fresh可执行卡的P1，晚于03:34:35Z实际合入。
本线程亲自读取review body及commit_id，inline列表为空不等于没有评论。
原独立组合38020976416和发布38021050451已成功，CI绿与此未裁定P1必须分别记录；
此前“无当前确定阻断”仅原窄审历史结论，PR16整体接受结论现暂停，不称develop无未结风险。
父任务已派原作者task/harness-manual-hold-identity复现/最小修复并等待真实Claude评审，
本线程不擅自回滚、重复合入或并行改实现。新修复需固定源门禁、独立组合及机器人精确head
review终态/未处理意见裁定。此后不mark-ready即merge，其他入口提前合入须合后补查与报告。

### PR27：修正任务索引的历史状态（2026-10-10）

冻结源 `1e78c1c091a6a392629e544c93048f633fbdc888`，合前 develop
`e192a32ebe659160cb64a1d4bd5df0b93bfdb74f`。README 单段明确旧“未发布/未编码”仅为
2026-10-08 状态，保留后续集成和未验范围；独立复审核 133 个链接目标及 diff 检查通过。
[源 push CI38023574770](https://github.com/mightyoung/Muyon/actions/runs/38023574770) 与
[PR组合 CI38023593893](https://github.com/mightyoung/Muyon/actions/runs/38023593893) 均成功。
[固定 head 机器人审查](https://github.com/mightyoung/Muyon/pull/27#issuecomment-6093816261)
已终结且无发现；合前另核完整评论、review body、inline threads 均无未结意见。
按用户授权正常 no-ff 合入 `55ab4db03aa5b18de6480e3e4e1e478ec2c2b83b`，整树等于已测源 tree。
发布 HEAD、ls-remote 和发布 CI 终态见执行回报，不以 source CI 代替发布结果。

PR20 源 `204f9a71a4ab7d8f6075270686e5891467867929` 的源/组合 CI 虽成功，
但[新 P2](https://github.com/mightyoung/Muyon/pull/20#discussion_r4236403656)经独立复审确认：
已消费核实后 fresh prepare 失败仍保留旧 hold 标记，恢复重复要求核实；现有回归未覆盖。
继续暂停，原作者补故障回归和持久消费状态后复审；不称 PR16 P1 已整体闭环。
PR21/28 仍按纯接口/typed 机制范围及组合依赖推进，不记 runtime、collection 或33组件完成。

### PR20：manual hold 身份保持与确认消费复审后合入（2026-10-10）

冻结源 `609e724874e5112152b06dfa7856f877cd2e413a`，合前 develop
`b142e6591ec66a5e9f0e68fb21e064ce17d0aa9f`。原 PR16 manual hold 重复 pause/resume
历史身份丢失 P1 及 PR20 确认后 prepare 失败重复核实 P2，均按本次固定源重新复审，
不沿用旧 head 的无阻断结论。核实确认在同一事务消费 hold、记录旧调用绑定的 acknowledgement；
fresh prepare 失败和重开重试保持预算及历史身份，新 invocation 仍走独立授权与未知回执停止。
27 项 manual hold 回归保留，新增四种 prepare 故障回归与先行 RED 文件逐字一致。
[源 push CI38025585341](https://github.com/mightyoung/Muyon/actions/runs/38025585341) 与
[PR CI38025588960](https://github.com/mightyoung/Muyon/actions/runs/38025588960) 均成功。
父任务核实真实 Claude 两轮 success/end_turn；本线程另派非作者独立 exact-head 复审，
无当前确定阻断。事务 rollback、acknowledged queued 崩溃窗口与有效 grant 专项补测仍为
非阻断剩余验证，静态核对不记为故障注入通过。
[新 head bot 复审](https://github.com/mightyoung/Muyon/pull/20#issuecomment-6094110047)
已终结且无主要问题；旧 P2 r4236403656 据修复机制及保留回归明确裁定已修复，thread 已关闭。
合前再次核完整 review body、issue/inline 评论，没有新增未裁定意见。
当前 develop 正常组合 `07d56654123c4be275ccf3789dcead15ce685f3e` 的
[CI38026717599](https://github.com/mightyoung/Muyon/actions/runs/38026717599) 成功，
analyze/test 8/8、host 1486/3skip、Laya 全通过。按用户授权正常 no-ff 合入
`5e7c3036f10f928665fea5f162ff3ad8052a4057`，整树与该已测组合完全一致；仅另附本摘要。
发布完整 HEAD、远端读回及对应 CI 终态见执行回报，不以源或组合 CI 代替发布结果。
PR21/28/29/30 和 coverage/lint 其余候选仍各按独立门禁处理，不随 PR20 批量合入。

### PR29：supplier owner lint 复审及最新 develop 组合后合入（2026-10-10）

冻结源 `a77aec123dc986eb0c9f5e7a244d41c2729c84d4`，合前 develop
`7773b7d96bc99f173b57a723d61526fba0df49ff`。五文件 17+/11- 仅 braces、wildcard、
typed File iteration 和 named initializing formal；安全/信任断言、重放保护及清理顺序保留。
完整 diff 和非作者独立复审无当前确定阻断；Dart 下限及调用参数名/类型保持兼容。
[源 push CI38024379339](https://github.com/mightyoung/Muyon/actions/runs/38024379339) 与
[PR CI38024403409](https://github.com/mightyoung/Muyon/actions/runs/38024403409) 均成功。
[固定源 bot 复审](https://github.com/mightyoung/Muyon/pull/29#issuecomment-6094367458)
已终结且无主要问题；合前重读全部评论、review body 和 inline threads 无新增未裁定意见。
旧质量组合 CI38024433993 因其他 owner 的 API45/UI37 analyze infos 失败，supplier analyze
及八套测试通过；本次未复用其接受结论，也未弱化严格 analyze 门禁。
最新 develop 正常组合 `961a3e49acfd26808b7e8c92c4cadebba8fa1b5a` 的
[CI38028993444](https://github.com/mightyoung/Muyon/actions/runs/38028993444) 成功：analyze/test
8/8、host1486/3skip、supplier498/4skip、doctor23、Laya29。正常 no-ff 合入
`ad1d3cf3b49c6686bf63554c0e9798ecea83b148`，整树与已测组合相同，仅另附本摘要。
发布 HEAD、远端读回及对应 CI 终态见执行回报，不以源或组合 CI 代替发布结果。
PR32 文档新依赖顺序 P2、PR28 当前四项契约/回调阻断均另交作者处理，未随本次合入；
PR21/30 仍待依赖验收与新组合，coverage 候选仍按独立门禁推进。
