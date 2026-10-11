# OIUI 调研建议排期（2026-10-11）

用户批准按下列顺序登记设计/排期。统一前置条件是 **SN6交付、与最新develop整链组合CI成功、CR18统一审查放行**；完整方案由统筹后续交付。原仓快照定位由用户提供：`f6e4388b26a64b9a0714943b08a1ce622b924eec`，尚未独立读取原仓；本次核Muyon基线 `330020c07af3431047ceefc05f76b1b5abc332ba`。这些是待设计小任务，尚无实现派发或完成证据。

1. **受限呈现目的与可解释降级**：在现catalog范围内声明呈现目的，无法满足时给可解释的降级；引用现有三档/少用策略与宿主请求冻结规则，避免重复其实现。
2. **绘制层刷新合并与稳定预览**：仅合并绘制层刷新，沿用业务更新、授权、formula及CAS的既有时序/边界；完整方案待补。
3. **宿主确定性what-if只读询价样板**：复用现catalog/formula/CAS，明确假设、只读数据与确定性计算，作为既有询价场景的样板；完整方案待补。

三项均保持受限呈现，不引入任意HTML/JS、Jev在线依赖，不把sendPrompt当用户授权。既有同需求先引用，避免重复实现；依赖未放行前不插队实施。关联总设计：[AI原生UI](../design/ai-native-ui-redesign-2026-10-09.md)，交接：[HANDOVER-LEADER](HANDOVER-LEADER.md)。

## 后续只读核对与排期细化（待动态验证）

来源为用户转交的只读交叉审查；原报告未运行测试。本次只读核Muyon已合8b01223918e45bc0c3340ab1e3c5e13e45fe9502（覆盖330基线）、PR52固定11225c4f2823ab45cb1e9421aeda0eb03969be95。OIUI原仓f6e4388仅为用户提供来源定位，完整方案/原仓读取仍待交。SN6当前远端f21719c1bc486d9a4482627ba03c030230cd8a9f仅任务说明，没有实现交付；不据此准备或放行AIUI组合。

- **发布合并与DraftFeed.abandon**：只合并绘制/发布层刷新，业务/CAS/权限检查时序不合并；终态、取消、撤权立即发布。PR52 drain finally确有无条件flush（agent_model_turn.dart637–639），DraftFeed有timer且无终止后封闭状态；尚未动态复现取消后尾段/安全绕过。abandon要取消timer并封住迟到delta竞态，不能只改finally。
- **CF2固定原因码**：并入既有CF2范围，不另派重复实现。保留batch Motivation provider取模型reasonCode的分支（develop ui_planning.dart287、PR52同文件667；tool39/42原样进摘要/data）需要宿主白名单；区分用户档位、宿主降级、模型不出卡三类固定中文解释。native stream成功已由宿主常量validated_stream_2给出（PR52 stream_ui_planning.dart118），不能泛化全部stream皆原样用模型原因码。
- **数据源A与只读试算卡B**：formula白名单/重算adapter已合；生产lib中未找到其具体实例接线，adapter明确只接受minimal-1/dynamic-1，library-2 fail closed。首版固定宿主模板复用已有catalog/formula/CAS，commercial不送模型；模板不自动赋予原值访问权限。
- **原值入口的范围**：ontology_card_snapshot.dart82排除credential，115–129所有非none字段当前/建议均“已遮盖”。当前已读的AIUI投影链未核得显式绑定原值揭示入口，先列数据源A依赖，不能绕过遮盖。普通原生业务UI已有用户本地查看路径：quotes_page显示单价，openRecord quotation打开quote form，其控制器读取price/extra_cost；项目预算/表单显示unit_cost、contract_amount等commercial原字段。这是既有原生业务查看，**不等于已提供AIUI遮盖值的显式揭示机制或授予模型读取权**；本次未跑这些入口的运行时验收。
- **零写入验收**：新数据源/试算样板跨新只读连接核领域与宿主完整快照，包括两张变更日志和出站账本；不能只用同连接total_changes作完整证据。

用户最终限定的撤权待实施设计：读取权限撤回、scope或object pin失效时，停止发布及动作，清该权限支撑的生成正文、卡片、来源展开和展示恢复缓存，仅留无敏感通用提示；来源依赖不能可靠归因时清整块依赖结果，不猜“安全片段”。只撤执行权限或用户取消且读取仍成立，保留已展示合法只读内容，禁止追加尾段与动作。用户原创消息不删除。沿用ui_stream_task_view重读clear，并另核普通DraftView正文防线及timer/迟到delta。**以上均待动态验证，不声称已复现安全绕过；不插入当前放行链。**

后续顺序细化为发布合并+abandon、CF2原因码、数据源A、试算卡B；均仍依赖SN6/整链CI/CR18放行。现有同需求先引用，不重复派发或抢占活动writer。
