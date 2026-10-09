# AIUI-4 F4a/F4b 集成复核（补验已关闭）

冻结 `fc02783ad078fd0cd90f577bb7cfe129e22f19d9`，基线 develop
`6e40a7956f2deb3ff53ee0397ae7cb4e1065c83d`。两位非作者独立只读复核32文件，
无确定运行阻断；有一项本轮应改测试缺口，关闭前不推组合、不合develop。

## 首轮应改：200%活动工作区验收（历史，已关闭）

`responsive_shell_test.dart:33`仅200%空外壳；accessibility/pane活动workspace测试均默认字号。
需原执行者补公开dynamic fixture：200%下完整确认正文可达且无overflow；1250/1280等宽度
退route/足宽pane，保持同controller且业务调用0。任务书§5明确要求，已有CI不覆盖未注册场景。
不要求新typed/collection或F4c实现，不改设计。按REVIEW交回作者补测试及精确新CI后复审。

## 已通过的独立核实

四枚举默认助手、IndexedStack/稳定key保持输入模型滚动；同session route/pane、字号测量退路、
48触区语义、真实ObjectRef/lease与旧插件入口断言保持，没有弱化旧断言/skip换绿。
CAS冲突保留输入，pending只查receipt不重放，宿主换代退役导航树/监听并等待lease释放。

`b411713db530e287a27153421a1341d2f2d70a8a`用单harness deadline，返回前await请求级cancel
落库，expired挡晚发送；repository既有terminal拒写挡晚GateConfirm resurrect。
两个受控Timer/startup屏障取代旧50ms等待，立即断言cancelled且保hasLength(1)。
这是实质修复已观察到的超时waitingConfirmation残留竞态，不证明覆盖所有未来取消场景。

已直接核[完整CI37988312269](https://github.com/mightyoung/Muyon/actions/runs/37988312269)
completed/success（run head fc027，实际PRmerge f9a27df3fb44bc77ca0a1e848f72e705cb2aca3e，
双父6e40develop+fc027任务）；本地正常组合产品/测试树与该自动组合一致、无冲突。
analyze8/8、test8/8、host1346~3、UI323~152。
[定向CI37988315500](https://github.com/mightyoung/Muyon/actions/runs/37988315500)
实测取消2、SQLite3、八文件47、旧导航5，共57通过。

有效变异对齐8779f2f最终runtime：b41cfad删除close checkpoint/flush，
[37985999347](https://github.com/mightyoung/Muyon/actions/runs/37985999347)指定close测试
Expected1/Actual0；5840526在restore重发confirm，
[37986006845](https://github.com/mightyoung/Muyon/actions/runs/37986006845)指定pending测试
业务调用Expected0/Actual1。均真实行为失败，不以启动错误/超时当检出。

范围/限制：仅F4a/F4b，snapshot刷新测试是卸载重开保override，并非同session热替换plan。
F4c/AIUI5接线、stream/2正式决定、真机/强杀/读屏/Mac golden均未完成或未授权。
本机无Flutter/Dart，运行依据精确CI；原始日志不入库。T3不纳入本轮。

## 最终补验复审

最终冻结 `140068385a3b499c13b2ec24af4ed7c30e4f0a4c`，两位独立只读复审通过，无新增阻断/应改。
相对前轮仅pane10行及测试130行；旧断言未删改。新test覆盖1250/1280@1x pane→
1250/1280@2x route→1920@2x pane→390@2x route，同controller/单body/route数量均实断言。
完整确认payload无maxLines/ellipsis、RenderParagraph未截断，tail selection boxes实际在viewport；
说明与确认/拒绝按钮hitTestable、48触区、enabled、businessCalls0/operationRefs空、无overflow。

[RED37990970640](https://github.com/mightyoung/Muyon/actions/runs/37990970640)新增用例在1920@2x
真实失败(Expected1/Actual0)，检出covered phone route未回pane；不是loader错误。
State.build订阅MediaQuery viewport/字体依赖，修复offstage LayoutBuilder旧约束不能驱动切换。
现有full-window host符合viewport策略；present仍复用同session，无新增controller/router/lease。
mounted/session guards及关闭/restore/dispose不变，b411取消代码完全未改。

[最终完整CI37991515411](https://github.com/mightyoung/Muyon/actions/runs/37991515411)
completed/success：run head精确140068，实际PRmerge b2744ae93701cfcd135925cffb9a7e8ed730eef2，
双父6e40develop+140068任务；本地组合产品树一致。analyze8/8、test8/8、host1347~3。
[定向37991523315](https://github.com/mightyoung/Muyon/actions/runs/37991523315)为review56d3441
组合运行，源apps/packages与任务相同、仅临时runner不同，实际58项通过。
支持进入唯一集成组合门禁，成功才发布；F4c、同session新版plan热替换及设备/golden限制保持。
