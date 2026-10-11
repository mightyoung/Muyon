# RS1：research-skill v6.8 独立组合复验

固定作者 GREEN `1d4bf256155ef0d5d313d3c2175dbed97591492a`，RED `81b4921ef27469d77d6277baaa25bdda98b75de4`，任务 `0a7b01950d5b239ca0965f7b991ce7b7c491bfcc`（父140a1b3）。最新develop基线 `fc9d73988ba20c2bda331614dfe8a16a83db165e`，已含OC15–20/WC-C及固定ADR/CR15–17；本次不是作者旧基线CI的延用。

独立普通组合 `bdb0a767f7926e8854d60c718f2d5c79a19b048e`（父fc9d739 + 1d4bf256），再独立修正两个夹具枚举，最终可执行候选 **`115bd91915068a3b0f01e2dbb8df4cd04c254adf`**。作者实现两提交7文件+203/-3，完整依赖含任务说明，组合8文件+229/-3；审查补丁只替换测试role/intent两值，生产research_module/lib逐字等于固定1d4bf256，无作者分支改动、无断言删除或放宽。

## 契约与静态范围

读RS-1、REVIEW/invariants、已合f7c76fd ADR第3条以及CR17决定。只读核对[上游固定UPSTREAM](https://github.com/mightyoung/research-skill/blob/49d97304eaae123d1075fc16bd98e37be9b831ad/UPSTREAM.json)与[evidence schema](https://github.com/mightyoung/research-skill/blob/49d97304eaae123d1075fc16bd98e37be9b831ad/references/evidence-schema.md)：local_schema_version=2，local_revision=2026-10-04-v6.8-own-assertions；role枚举supports/refutes/context，intent枚举known_item/exploratory/snowball。外部文档仅作合同参考，不调用该skill或上游写入脚本。

skillKinds接入assertions，导入分发表、WB引用解析、工作台分类共享它；skillKindLabels显示“研究者主张”，_newlyRecognised为原other行的无歧义重新识别保留本地ID。所有新增展示/引用沿原只读数据视图，无新增上游assertions.jsonl回写或assertions专用导出，V1/V2仍取schema_version==2，claim草稿生成代码未改。既有通用report/task导出路径也未改；本次不把“未新增专用导出”夸称为所有既有通用出口都新增了全局assertions禁出规则。

## 非阻断夹具修正与实际测试

Parent安排的独立只读兼容审查指出原测试role='support'、intent='寻找反证'不属于v6.8枚举。按用户建议及REVIEW小而确定修改规则，仅在review分支替换为supports/exploratory，提交115bd919；原作者7文件与来源保留。这修正两处枚举值，不声称最小合成夹具已经通过整个上游严格校验，其他未知可选字段刻意用于验证宽容读取和完整JSON值保留。

官方Flutter3.47.5/Dart3.13.4；缓存/生成配置处理沿既有隔离验证流程，平台文件未提交：

- 原作者字节目标research_skill_test + skill_ui_test：24pass/0skip/0fail。
- 两逆变异恢复、枚举修正后research_module完整：236pass/0skip/0fail；research_module与apps/muyon strict analyze均No issues found。
- 新增5用例覆盖：assertions导入完整原始JSON及可选intent/decisive_neighbors/结构化critical_unknown/future_optional，旧项目缺日志仍读，other重分类保持本地ID，WB格式/解析坏rev，只读分类原始行展示、精确旧r1并提示新r2与缺失引用、generic项目仍隐藏assertions。
- claim草稿的既有验证留在236项全量内；未改草稿格式、固定paper修订或V1/V2逻辑，不将读取展示测试说成科学结论或全量上游结构认证。

## 必需逆变异：独立施加、逐项还原

| 逆变异 | 结果与失败第一行 |
|---|---|
| skillKinds移除assertions | 21pass/3fail，首行`v6.8 assertions import preserves optional fields and references [E]`；Expected length1 / Actual0；两个展示/旧修订引用用例也检出 |
| 导入Map.from后删除未知future_optional字段 | 23pass/1fail，同一导入用例首行；Expected完整原始Map / Actual缺nested future_optional |

两项均编译/启动正常，抓到业务/显示断言，不把加载错误或清理连锁当行为证据。原始日志和临时脚本不入Git，产品逐字还原；只有明确来源的两值夹具补丁留在正式候选。

## 作者列表preview失败归因：独立基线对照

作者原环境失败的原始全量日志/根因未独立重建，不能直接采信“基线也有”。同SDK、Linux、测试参数与原生缓存，独立detached基线fc9d739和组合分别执行：

| 范围 | 最新develop基线fc9d739 | RS1组合 |
|---|---:|---:|
| list_preview_distinguishes_candidates_and_actual_quote单例 | 1pass/0fail | 1pass/0fail |
| inquiry_list_import_pipeline_test.dart全文件 | 14pass/0fail | 14pass/0fail |

基线已有合后CI38148301330 host1849pass/3skip，原始checkout与终态已核；包含该文件的正常全量通过。本次Linux样本没有复现作者列表失败，未证实其原平台基线归因，也未声称修复了偶发失败。没有修改列表产品/测试、超时、skip、CI或baseline来过门禁。新完整组合的host全量证据另列。

## 精确远端CI与结论

作者[source CI38147758890](https://github.com/mightyoung/Muyon/actions/runs/38147758890) completed/success（14:53:11 UTC），原始checkout精确1d4bf256完整SHA；3544pass/207skip/0fail，research236、host1824/3。这是旧140a基线，不替代当前fc9d739组合。

最终独立[组合CI38151075130](https://github.com/mightyoung/Muyon/actions/runs/38151075130)：completed/success（15:42:28 UTC），8包analyze/8套测试均通过，3569pass/207skip/0fail，Doctor23、Laya、coverage与制品步骤均success，原始checkout与metadata必须精确115bd91915068a3b0f01e2dbb8df4cd04c254adf。
| suite | pass | skip | fail |
|---|---:|---:|---:|
| module_api | 250 | 0 | 0 |
| muyon_ui | 380 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 236 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 1849 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |


结论：**RS1固定源与明确标注的两值夹具修正可按授权合入**。独立阅读无新增Critical/Important；Parent只读兼容初核无静态阻断，指出的枚举夹具问题在review候选修正。科研236全量、两个逆变异与最新develop完整八套证据通过；作者列表preview失败未在本次Linux单例/全文件/组合全量复现，不声称已经独立证明其原平台基线归因或修复偶发失败。

报告docs-only后继没有自己的完整CI，须与115bd919代码/夹具候选区分；按授权正常合入后另读完整develop SHA和合后CI终态。main、作者及审查分支保留。不导出MUYON_EVAL_REAL，不执行真实模型/Android，不强推、删分支、回退或部署。LE01两个Important仍待Sonnet补修；其审查文档abf9f9e在独立review分支，没有借RS1合入develop。WC-D-F仍待交且优先；AIUI需SN6/CR18统一外审，不纳入此批。
