# PR42 / SN-2 / SN-3 集成修复

状态：源码候选交付统一复审；本页记录发布检查点，最终完整远端 SHA 与对应 CI 终态见任务分支关联草稿 PR。不以静态复核替代 CI；未合入 develop，未执行真实模型或设备冒烟。

## 冻结来源

- develop：`56a7d8a898a9cf528f64b24f69c91d6cf44a5b2e`，含 SN-1 与 OC-11。
- 原 PR42：`c7bbc9497107984e4ef665ca8a2ea9b2568aa721`。
- 独立修复分支：`task/pr42-sn2-sn3-repair-20261011`。
- 本地集成提交：`ee839589338d6cc7ebc8e88724ee115e7b9cc757`。只协调外部污染 probe 的重复声明与参数；宿主未知污染仍按需要确认处理，OC-11 事实读取逻辑未改。

本轮只交付独立任务分支，由统一入口复审；不更新 develop/main，不删除远端分支，不执行打包或部署。

## 行为与证据边界

1. 无效行、缺 end、限制超出、最终校验失败、超时与传输失败保留只读预览及宿主事实回退；失败结果不携带执行能力。诊断使用稳定原因码，原始异常文本不进入持久证据。
2. 按 [流式合同](../design/aiui-stream-contract.md)，第一个有效 end 后的协议行忽略并记 `after_end`。按 ADR-0001 已采纳的 CR-3，真正传输错误须另外记录，并撤销执行能力，保留原编译校验结果。
3. 三档偏好约束已打开工作区和旧回调。少用的明确请求来自宿主入口、绑定本次身份；切换偏好或建立新身份不能恢复旧呈现资格。必需任务批准与拒绝控件仍独立保留。
4. 模型目录只列出当前请求实际可用的 `assistant.plan_ui`；JSON、native 与系统元数据一致。任务列表先过滤、去重，再做最近与较旧父任务切片，内部待确认任务保持必需控件。
5. 动态批卡尚无逐项执行语义，因此“逐项决定”必须禁用，不转为整批确认。
6. 污点变化刷新已显示卡片。捕获与路由边界复查计划身份、修订、草稿、宿主污染与来源身份，并在参数映射后再次检查；未知宿主事实保持拒绝。

原 `aiui6_stream_production_test.dart` 中 after-end 失败/清空预览的断言与已有合同不一致。迁移只限这些具体预期：失败仍须拒绝最终能力，新增只读与持久诊断断言；不得删除负例或放宽全库门禁。

## 测试先行记录

- SN-3：20 个行为例，测试提交 `a1bbc3623c620086d729903e95a88de01f1b1362`，CI [38113721137](https://github.com/mightyoung/Muyon/actions/runs/38113721137)。终态 FAILURE；宿主 1684 pass / 3 skip / 24 fail。确认失败预览清空、after-end 抛错、持久诊断缺失、迟到能力复活等目标断言真实失败。
- SN-2 目录与列表：14 例，测试提交 `d6b9354efdf54dd899d78447230375f476a6b5f2`，CI [38114003200](https://github.com/mightyoung/Muyon/actions/runs/38114003200)。终态 FAILURE，JSON/native 不可用工具广告真实失败。少用正对照随后补齐已保存公开回答前提；列表旧测试视口不足，列表失败不能计为行为 RED，已用 `3a7a346fdef1aee38f3be1d06495ed37aea257ef` 扩大视口且保留全部断言，CI [38115229194](https://github.com/mightyoung/Muyon/actions/runs/38115229194) 终态 FAILURE；扩大视口后真实发现 parent-8 重复卡片，三种模式均失败，列表修复未削弱断言。
- 已打开工作区：7 例，公开回答前提已补齐，提交 `eb96a891eb670460ed073f16cfccb56666412810`，CI [38114255906](https://github.com/mightyoung/Muyon/actions/runs/38114255906) 终态 FAILURE；宿主 1687 pass / 3 skip / 42 fail。两档模式撤销仍显示动态 UI、旧回调把草稿 12 改成 999、少用 ABA 仍显示、逐项决定回调非空，均取得真实行为 RED；既有污染刷新例已运行，不伪称它也失败。
- 路由边界：8 例，含真实待确认工具任务正对照；实际取消例一起在 `3dde5460e5c63f3ee7ca57e8fc3925963512d399`，CI [38114558281](https://github.com/mightyoung/Muyon/actions/runs/38114558281) 终态 FAILURE。五个映射后/身份/污染变化负例真实错误接纳；另两个同步刷新负例及正对照原已通过。实际取消例因错误夹具使用非成功任务的 assistantAnswer 参数失败，不计为取消 RED；修正夹具基线 `eef4276e9db0483c027ce2f9be7a2ef33a55ae47`，CI [38115958666](https://github.com/mightyoung/Muyon/actions/runs/38115958666) 终态 FAILURE，宿主 1690 pass / 3 skip / 49 fail；原任务真实取消后 preview 为 null，确认为取消退路 RED。该基线不含最终来源读取等待中的专门竞态例，不能挪用其 invalidation 失败作为该竞态的证据。
- 目录撤销：新增 4 例，JSON/native × 切文字/撤 provider，断言目录只缩小、三处一致及普通系统字段完整保留；`f8eb39361955b09e183e078687acaa9ae365ffc8`，CI [38115409889](https://github.com/mightyoung/Muyon/actions/runs/38115409889) 终态 FAILURE，但四例在模型请求数为零的前置条件失败，不计为撤回 RED。精确隔离此前 widget 注册的假 HTTP、保留全部请求/工具/目录断言后，重新发布 `dd7bc29b734a11f9682a652ce9ee0c7b16392d68`，CI [38116815839](https://github.com/mightyoung/Muyon/actions/runs/38116815839) 终态 FAILURE；宿主 1728 pass / 3 skip / 22 fail。四例均通过请求数、真实 read 工具及下一模型轮前提，再于旧 uiPlanningContext 残留断言失败，取得可靠撤销 RED。源码负分支现精确删除该工具与旧宿主提示，候选只缩小，其他系统字段保留，待最终组合验收。
- 第一生产修复：`5757742918372a0a4ab15a669a737d5ce11351a8`，CI [38115431423](https://github.com/mightyoung/Muyon/actions/runs/38115431423) 终态 FAILURE；宿主 1716 pass / 3 skip / 31 fail。它尚未包含工作区、路由和后续目录撤销修复，不作最终 GREEN 证据。

精确旧测试迁移：HK-2 和真实业务路由夹具先保存 automatic，再从真实 start 冻结请求，保留缺端口/待回执/无假成功/实际业务确认写入检查；HK-2 textOnly 的旧可点击动态卡断言按采用决定迁移为隐藏动态卡、原答保留、零回调、零工具。设置失败 widget 测试仍执行真实选择和 SQLite 拒写，选择 tap 放在 real async zone，以免真实数据库队列清理等待已暂停的 fake clock；失败回滚、重试、持久设置、零权限零工具断言保留。

当前云端工作区没有 Flutter/Dart。官方 SDK 获取受环境网络限制，未更改版本、代理、权限或工作流；本地不能提供 Flutter PASS。正常 Actions 已完成 SDK 设置，使用未削弱的 `scripts/ci.sh` 验证全库。最终交付必须补齐新组合 SHA 的终态 CI、独立复审及剩余验证清单。

## 独立复审后的补充边界

独立复审 `ee839589338d6cc7ebc8e88724ee115e7b9cc757` → 本地 `1df1ec1ed36926d6488249a6e965491119ed06ce` 提出三个 Important 阻断：最终宿主来源读取等待中取消可恢复旧成功结果、新宿主请求身份尚未触发 repository 通知时旧本地编辑仍可执行、自定义业务端口未拒绝未知宿主事实。补充测试基线 `5cd9bb975cf4e533b3cad920d3c6b5ec0b414c4e`，CI [38116294660](https://github.com/mightyoung/Muyon/actions/runs/38116294660) 终态 FAILURE，宿主 1728 pass / 3 skip / 22 fail；新身份编辑（12→999）与 unknown 自定义端口（接收到 UiEvent）取得真实 RED。最终来源等待取消例没有保存公开回答、无法进入检查点而 2 分钟超时，不计为该竞态 RED；原任务取消例混用 fake/real async zone 超时，不计为行为结论。两项夹具精确修正且保留全部原断言，再增加未进入检查点时明确失败的前提检查，测试基线 `005803269590b5df3641b6c47236c7eca0e3b1c0` 已发布，CI [38117690999](https://github.com/mightyoung/Muyon/actions/runs/38117690999) 终态 FAILURE，宿主 1729 pass / 3 skip / 21 fail。最终来源检查例真实进入检查点后于返回 validated 断言失败（Expected null / Actual ValidatedUiPlan），取得可靠 RED；原任务取消例精确异步夹具修正后通过。取消终态复核已补于本地 `dcb6904`，待组合验收。

新身份同步撤销的独立基线 `37b0ebe39406da84e2e1148423e38b1287afc06f`，CI [38115586976](https://github.com/mightyoung/Muyon/actions/runs/38115586976) 终态 FAILURE，真实捕获旧回调将草稿 12 改为 999；已据此增加实时只读探针。

Git HTTPS 写认证在本轮中途不可用。没有修改认证配置、权限或凭据；使用现有授权 GitHub 连接器创建 Git 对象及任务分支，每次发布先核对 API tree 与本地不可变提交 tree 一致，再以正常前进方式写任务 ref。原 PR42、develop/main 保持未写。

独立静态补充复查已确认 provider 的最后只读预览恢复（所有 events 清空、无 finalPlan、保留编译证据）、workspace 实时 readOnlyProbe（同步复查冻结身份）、最终来源读取后复核取消终态及 custom sink unknown 拒绝没有新增阻断。这些源码仍须最终组合 CI，目录正分支的来源可用性问题仍阻断交付。

上述补充 CI 中已打开模式策略、五个路由负例与设置保存重试未再失败；它仍有 22 项宿主失败，不能替代最终新组合 GREEN。

unknown 自定义端口的同步拒绝及真实宿主 clean 正对照已通过独立静态复核：没有直接伪造 facts、签发审批或扩大本地拒绝/semantic 拦截。源码补充本地提交 `9e03b9b7521027694a50ee1c5fdc719e10fe1d6e`，仍需最终组合 CI。

本轮派生的 `*-red*` 分支仅作为测试基线，不是生产合入候选。develop 经 `FETCH_HEAD` 与 `git ls-remote` 冻结为 `e7af6ab4877fcd6e5c8cc69c5168c5ce5ee42697`，包含已合的 REG3c 与 GB6；已正常 merge 到独立修复分支，没有冲突或向 develop 写入。当前远端 fetch 配置只跟踪 main，不能把过期 origin/develop 当作最新基线。

独立复查进一步发现目录正分支在 source null/throw 或 await 期间撤销时仍可保留广告。新增 JSON/native 共 8 个负例（目录测试总计 26 例），均检查首轮已持有提示、真实 HTTP/read/下一轮以及受控 source 入口；基线 `91400c3380ee2038fca3caeb7ecfe654d9e4424b`，CI [38118514577](https://github.com/mightyoung/Muyon/actions/runs/38118514577) 终态 FAILURE：宿主 1740 pass / 3 skip / 18 fail，八个新增来源负例均通过真实请求/read/下一轮及 source 入口前提，在旧元数据残留断言失败，取得真实 RED，无超时。supplier_core 为 498 pass / 4 skip，不延续上一轮期限失败。另补 JSON/native × 非流式 provider 切到实际流式 provider、冻结 non-streaming profile 两例（总计 28），保留真实请求/read/下一轮前提；基线 `9af5397f982213493b664e96c563aa15f89669ce` 已包含最新 develop 与取消竞态源码，CI [38119236132](https://github.com/mightyoung/Muyon/actions/runs/38119236132) 终态 FAILURE，宿主 1777 pass / 3 skip / 20 fail；两例均通过实际 non-stream 请求、read 与下一模型轮，再在元数据残留断言失败。此 SHA 为 profile-red 测试基线，不作实际 fix 候选验收的最终失败结论。两者均不是最终生产验证。

`38117690999` 的 supplier_core 另有 497 pass / 4 skip / 1 fail：未修改的 lan_security 绝对期限测试第二个 1 字节上传在 flush 阶段超 150ms，返回 HTTP 400。本轮没有 supplier_core 源码差异，没有修改该断言、超时或门禁。最终新组合仍须全量 GREEN，不把这一失败豁免。

来源正分支的 null/throw/await 后撤销已补统一前后可用性检查；两个旧 JSON 撤回例的 stage failed 定位为重建 message 的运行时 Map<dynamic,dynamic> 不符合 freezeJsonMap，已精确改为 String-key Map，其他字段与工具保留。六个 mandatory 批准控件仍被输入区遮挡，源码现优先显示待确认卡片并将同一动作 Wrap 放在卡片开头，完整说明仍可滚动，测试与控件尺寸未改。旧 external-content once 正对照补齐真实 start 前 automatic 偏好，保留全部污染、审批、数量与回执检查。连同 analyzer 报告的八个 info 精确语法修复，源码冻结为本地 `ec6baeee36f542509c023c61054f67a7e80f9ebe`；实际 provider 与冻结 streaming profile 不匹配已取得上述两例 RED，并在统一前后门禁中增加实际 StreamMotivation provider 要求冻结 streaming 能力的最小检查。

最新 develop 组合又揭示 GB6 closing-during-prepare 回归（Expected interrupted / Actual failed）：PR42 新增 close 清理 await 在登记关闭终态之前让出执行，即使等待 null 也可令 prepare catch 的 failed 先写入。源码已恢复旧终态先序，同步撤销呈现资格并启动偏好关闭，先取消 tokens、登记 queued/running 的 interrupted，再等待原三组清理及 active operations；GB6 测试和 dispatch 未改。最终源码候选本地 `c84b5ed3a10e6dc371dbc0e0d6a0e1517b5329cd`。发布检查点仍须新组合完整 analyze、全部套件及独立复核；最终 PR 应逐项补充确切 SHA、CI 终态及宿主摘要，不用 RED 基线或旧绿色替代。
