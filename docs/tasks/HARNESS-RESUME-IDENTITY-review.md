# PR16 恢复身份与工具进展预算：独立整合复审

日期2026-10-10。冻结源 `147ad71378af7ae7206b1e2c6ca2d76f98fc0639`，
develop基线 `cf672164e4f6c3e7beea8029c8be735e33c3bf19`，临时组合
`b70d377d138ec3631b64a3f0ec4072823779f015`。
源审查分支review/HARNESS-RESUME-IDENTITY-20261010；组合独立工作区
`/workspace/Muyon-resume-combination-20261010`，review/HARNESS-RESUME-combination-20261010。
已读HANDOVER/REVIEW/任务及既有架构用户决定；无AGENTS.md/.agents技能；本机无SDK。
按REVIEW派两位非作者只读核实者分别逐行核机制与行为测试，不修改/提交/推送。
父任务另转交4个真实Claude Sonnet5.5 low完整success/end_turn/exit0窄包，无确认阻断；
本线程不冒称实际执行Claude。

## 范围与逐项结论

源及组合增量均4文件，512新增/17删除：agent_resume.dart、tool_registry.dart、
agent_resume_test.dart、任务文档。metadata registry修改由正常merge自动组合，无冲突；
未改其binding/固定lane/授权校验。Dream、foundation、LAN、workflow/ci.sh、bootstrap不变。
恢复逻辑/测试/任务在组合中与精确源逐字一致，收据读取不触发metadata resolver。

| 判据 | 独立核实结论 |
| --- | --- |
| 身份来源 | 满足；ToolReceipt/receiptFor读取持久identity_digest；agent_resume:72/89/209比较历史提案摘要及tool ID，不依当前可变registry重新prepare |
| 异常/错配拒绝 | 满足；缺失/空白/非字符串/不匹配摘要不采纳已有回执，暂停核实；未知写入/外传不重发副作用 |
| 成功不重跑 | 满足；匹配历史成功直接复用，无重新prepare、审批或工具调用；真实approve/invoke回执测试核零重跑及零新增审批 |
| 正常再授权 | 满足；手动核实后回正常dispatch/授权，模型将未执行调用折叠为固定结果；无旁路审批或权限扩张 |
| 工具进展预算 | 满足；:274/279/330保留工具检查点及steps/active time/tokens；无回执/匹配失败回执/重复held不重置；孤儿确认耗尽的终态检查点保留 |
| 30新增行为回归 | 满足静态核实；真实prepare摘要差异与SQLite回执，原manual-running补正确摘要；旧行为断言无删除或放宽 |

未发现当前确定阻断；建议全套组合CI通过后合入。不是任意本地数据库篡改认证：
只改payload参数/scope而保留匹配历史摘要、同时改写提案/回执摘要均不在保证范围。
无工具检查点/进展的纯模型任务仍可能走既有fresh清预算，不宣称全部恢复连续。
动态夹具_crash仅改持久任务状态，未关闭重开数据库/模拟进程重启；不冒称进程重开、
断电/强杀、真机或真实模型取证。注入宿主时钟/reported token核1→2轮、20→40秒、
150→300 token；它是确定性预算行为测试，不是实机计时证据。

## 历史RED与最终源GREEN（已亲自读日志）

先行身份测试[38017735820](https://github.com/mightyoung/Muyon/actions/runs/38017735820)
实际checkout a5fe81f PR merge（8060d815121adae0fbf8252b467e304549b9dfc4 into3b0），
analyze8/8、host1366/3skip/10fail；身份旧行为失败，其他套件通过，Laya skipped。
中间身份修复[38018622999](https://github.com/mightyoung/Muyon/actions/runs/38018622999)
checkout07c8680 PR merge（0627b9f9c1f2b9a016ae0645e0fa2de064b4679f into3b0），
analyze8/8、host1389/3skip/2fail，恰无回执/匹配失败回执旧预算断言仍failed。
这些是保留的历史RED，不说它们在最终head仍失败，不声称30例全部先行RED。

最终source[38019568121](https://github.com/mightyoung/Muyon/actions/runs/38019568121)
精确checkout147ad713完整源，host1396/3skip、analyze/test8/8、doctor23、Laya8/4/8/9成功。
PR[38019570449](https://github.com/mightyoung/Muyon/actions/runs/38019570449)实际checkout
bd957be99bd4ae9318a4cc045e0535c13135ff02＝147ad713 into b8a9a523完整PR14发布，
host1434/3skip及全门禁成功。二者均不含最新Dream cf672，不能代替当前组合证据。

## 本线程主动发起固定组合门禁

精确组合b70d377推既有review/**，触发[38020976416](https://github.com/mightyoung/Muyon/actions/runs/38020976416)，
不新增workflow/runner/付费服务，不导出MUYON_EVAL_REAL，不安装本机SDK。
现有入口bash scripts/ci.sh：pub get、8包flutter analyze --no-pub（info失败）、gate回归、
doctor23、8套flutter test --no-pub --reporter compact --timeout 120s；host全test无过滤。
成功后既有Laya四组。此为独立主动组合验证，不仅采信作者报告。终态另补实际摘要。
原始RED/GREEN/组合日志仅Actions或/tmp，不进仓库。

## 集成边界

成功门槛后重核develop HEAD、正常merge/ff，无强推、远端分支删除、自动合并或部署。
同时携带PR15追补审查，保留PR14原发布cancelled与cf672后续组合success的不同记录。
历史LAN400仍“未重现、原因未明”，由独立LAN任务处理；不把本轮门禁成功写作修复LAN。
PR18及其他AIUI未来夹具/契约决定不捆绑，本片不采纳新schema或接UI runtime。

## 复审期间远端已合事实

API确认PR16由merged_by.login=`mightyoung`于`2026-10-10T03:34:35Z`合入develop，
merge SHA `38f2040bbdb7b7d0f766891c94c3440d208a7f6c`，源仍精确147ad713完整SHA。
此合入不是本线程执行，发生在本线程独立组合门禁尚未结束时；不推断具体会话责任。
fetch及git diff --exit-code核实38f2040整树与独立组合b70d377逐字一致（tree
`9a5e9b146feaeb814a9c642a11b6069b49a87a02`），源已在develop祖先中，不重复合入。
对应发布CI[38021050451](https://github.com/mightyoung/Muyon/actions/runs/38021050451)单独跟踪，
与本线程发起的review CI38020976416区分。两项终态后才下最终接受结论。

## 最终门禁与结论

独立组合38020976416/job114121670514在精确b70d377完整SHA、attempt1 completed/success；
发布38021050451/job114121900331在精确38f2040完整SHA、attempt1 completed/success。
已亲自读两项全文日志，均analyze8/8、test8/8、gate/doctor23及Laya8/4/8/9通过。
两项测试摘要均module_api68、UI323/152skip、prototype39/1skip、research220、
supplier490/4skip、host1459/3skip、preview15、inquiry289/47skip，无过滤或重试挑绿。
原始日志仅`/tmp/muyon-ci38020976416-job114121670514.log`与
`/tmp/muyon-ci38021050451-job114121900331.log`或Actions，不进仓库。
结论：当前源及同树组合无确定阻断，接受已合结果，不重复合入。收尾仅复审/索引/交接文档，
不改已测产品/测试/CI树；最终摘要发布SHA和对应CI单独由执行回报核实。
