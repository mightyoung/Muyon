# LE01 补修：独立合同、别名回归与组合复验

固定作者GREEN `bf63985a766f39912a53661bc63e37caa430ab7b`、RED `0e8d3dbab09fca6dfd4e89745da5f3f18e3758b6`、原LE01 `202e44afc793aba8f38d2fb4105aa6c656bbf8af`。原两个Important已在独立真实复现中确认，原阻断报告[abf9f9e](https://github.com/mightyoung/Muyon/blob/abf9f9e1ff43c4d3e01dc84c9c57d05249071c4b/docs/reviews/2026-10-11-le01-independent-blocking-review.md)保留，不改成原交付从未有问题。

作者补修三API文件+159/-9，两产品文件+38/-9及新增五回归。相对最新develop8b01223918e45bc0c3340ab1e3c5e13e45fe9502，完整LE01增量含原export/public类型、18合同测试与5别名测试。作者/依赖LE02/04/05分支均未改。独立review补一项mutable DestinationRule getters测试，明确保留const构造和非localExport原网络对象identity；不扩成任意原生恶意实现全封闭要求。

## 静态与动态合同

Parent非作者静态结论C0新I0，原两I闭合。localExport在ExternalToolSpec/ChannelSpec接收时复制Set并建立规范DestinationRule，校验的是保存的this.destination快照；准备内容将sources六字段/exclusions两字段逐值重建，bytes仍copy+unmodifiable。声明local_exports/本机出口不赋予写文件或另存为授权，本批仍是API合同，未接上真实系统保存。

独立使用官方Flutter3.47.5/Dart3.13.4、Linux，编译/启动正常，临时副本和日志不入仓库：

- 复用原公开完整三复现：GREEN **3pass/0fail**；临时恢复两产品文件为固定RED字节 **0pass/3fail**，第一行分别为I1 mutable hosts、I2 source identity/revision、I2 exclusion reason。行为失败，不计零测试启动错误作回归证据。
- 作者新增五测试在同一RED字节 **0pass/5fail**，包括channel与直接改暴露Set；原基线不足已被复现，而非仅接受作者数字。
- 七逆变异各自被原业务断言抓到，见下表；恢复后作者23目标及公开三复现与新增一项getter边界一并 **27pass/0skip/0fail**。
- 恢复后API全量 **274pass/0skip/0fail**；strict analyze No issues found。作者273与本次274差一项独立getter测试，没有删除/放宽断言或增加skip。

|临时逆变异|本次23作者目标实际结果|
|---|---|
|去掉缺local_exports capability拒绝|22pass/1fail，without capability is refused|
|允许mixed localExport/network|22pass/1fail，cannot be mixed with a network rule|
|保留caller Uint8List别名|22pass/1fail，caller bytes later change does not reach preparation|
|ExternalToolSpec跳过destination冻结|21pass/2fail，后来host变化、直接Set修改|
|ChannelSpec跳过destination冻结|22pass/1fail，channel keeps frozen destination|
|sources仅冻结List、元素保留别名|22pass/1fail，source element identity and revision|
|exclusions仅冻结List、元素保留别名|22pass/1fail，exclusion element reason|

独立补测用合法implements DestinationRule、初始localExport=true，构造工具及channel后改变三个getter/集合；二者保存的规范快照仍localExport=true/publicWeb=false/hosts empty。源与排除项用合法mutable implements实现，测试六字段/两字段全部快照。没有改作者产品来掩盖失败；临时逆变异结束后lib逐字等于bf完整SHA。

## 完整八套分母与旧floor复核

详细测量、制品摘要、428源码hash、全库存、DA/未命中身份、PR实际checkout与明确API门禁更新，见[覆盖率独立复核](LE01-freeze-coverage-review-20261011.md)。

第一次独立固定9ab723646c56a170fa9aa6da4ec86b33be03ff99的[38154755264](https://github.com/mightyoung/Muyon/actions/runs/38154755264)测量完成，仅旧API denominator drift失败；八套3632pass/207skip/0测试失败，不能称完整绿色CI（Laya当时跳过）。API库存37→38，2320/2446→2387/2514；registrar22/26→34/38、新local_export55/56。其余426加载源码DA和未命中身份均不变，models/transfer gate完全相同，无旧逐文件floor降低。

API-only实测2041/2514，与作者2042/2514及八套2387/2514分开，未用局部数字放行。只有经完整八套确认的API gate条目更新；其他门禁/历史顶层快照保留，不冒称整个baseline.json为新测量快照。checker/范围/skip/产品不改，无日志入仓。

最终候选 **`2938bceb6a4ed35e4c471860af4763228bb4413c`** 已普通合入最新develop8b（仅补文档）并加入明确API gate更新，八个lib树与9ab测量候选逐字相等；[完整组合38156140067](https://github.com/mightyoung/Muyon/actions/runs/38156140067)：completed/success（2026-10-11T16:55:12Z），metadata与原始checkout精确上述完整2938 SHA；8分析/8测试、Doctor23、Laya/coverage及制品全success；3632pass/207skip/0fail。

|suite|pass|skip|fail|
|---|---:|---:|---:|
|module_api|274|0|0|
|muyon_ui|380|152|0|
|prototype|39|1|0|
|research|236|0|0|
|supplier_core|498|4|0|
|host|1888|3|0|
|ui_preview|15|0|0|
|inquiry|302|47|0|

绿色制品11709490799 ZIP SHA256 `33f1f675e773453f6e5fb1cf500590e024baf87ca8c60f67f390cb9397a4d45c`。重新逐blob核428源码与全库存，完整DA/未命中身份与已审9ab测量逐项相同；模型/传输门禁仍完全相同；更新后的当前baseline比较错误集合为空。没有通过低floor、变更脚本、忽略文件或删除断言获得绿色。

## 放行与保留边界

两个原Important闭合、const/network兼容保持、七实际逆变异抓到、完整八套旧floor/新分母独立复核且最终完整绿色CI成功后，可按用户授权正常no-ff合入；合前核全部远端完整SHA与clean状态，合后另核精确develop终态。报告文档后继无自己的完整CI，执行证据固定2938，不移花接木。

WCDF先已闭环：develop8b01223918e45bc0c3340ab1e3c5e13e45fe9502 [38154862759](https://github.com/mightyoung/Muyon/actions/runs/38154862759) completed/success，2026-10-11T16:34:04Z，3608pass/207skip/0fail，原始checkout/8分析测试/doctor23/Laya/coverage全核。第6交接及唯一集成职责已登记，main与作者分支保留，PR50仍原base/open。

OIUI建议已只登记后置设计，SN6当前仍仅任务文档f21719c，无实现交付，AIUI整链与CR18放行门槛不变；commercial普通原生业务查看不等于AIUI显式揭示或模型读取授权。撤权/取消的生成正文、卡片/来源/恢复缓存及timer迟到delta设计均待动态验证，未宣称复现安全绕过。OC21已接手排在本批闭环后，精确六原测试、排除OC18；两位前作者零测试探针不算验收，不重复派发或改活动writer分支。

未调用真实模型/Android、不导出MUYON_EVAL_REAL、不强推/删分支/部署/回退。LE01原始阻断记录与新修复证据并存；LE02/04/05后续接线仍需各自作者固定交付与审查，不因API合同合入而自动放行。
