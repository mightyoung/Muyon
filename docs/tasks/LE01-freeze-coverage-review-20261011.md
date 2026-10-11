# LE01 补修：独立八套覆盖率与门禁更新复核

固定作者补修 `bf63985a766f39912a53661bc63e37caa430ab7b`，RED `0e8d3dbab09fca6dfd4e89745da5f3f18e3758b6`；原交付 `202e44afc793aba8f38d2fb4105aa6c656bbf8af`。作者三文件+159/-9仅改变API两个产品文件及五回归测试；公共const构造与非localExport原规则identity保持。组合以develop330020c07af3431047ceefc05f76b1b5abc332ba加入LE01补修和已绿WCDF d76；独立补一项mutable DestinationRule getters测试。测量候选完整 **`9ab723646c56a170fa9aa6da4ec86b33be03ff99`**。之后正常合入develop8b01223918e45bc0c3340ab1e3c5e13e45fe9502只新增四文档，八个lib树逐字未变。

## 测量终态与实际检出

[独立测量38154755264](https://github.com/mightyoung/Muyon/actions/runs/38154755264) completed/failure，2026-10-11T16:30:35Z；metadata与实际checkout精确9ab完整SHA。分析8/8、测试8/8和Doctor23全部通过，**3632pass/207skip/0测试失败**，完整ci-log制品确认唯一失败 `CI SUMMARY: FAILED (coverage:report)`，原因是保留旧API分母。Laya因前置失败被跳过，不称此run完整绿色CI。

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

coverage-summary制品11708680055，ZIP SHA256 `ffb4365e4f5618f654643d19348144eb38e7f97b96c5a47a05a9b465b78fef09`；完整ci-log制品11707629373，ZIP SHA256 `e8532bcf756e674e3712a8de6bf62df2f6cf75dd5a72c3a9471df5ebb3e8c272`。完整制品用GitHub只读下载核摘要。gh文本日志在巨大DA编码行后会缺后续step文本，故唯一失败分类读取完整ci-log，未仅凭截短文本猜测。

作者[PR CI38154167668](https://github.com/mightyoung/Muyon/actions/runs/38154167668)也是八套通过、仅旧API分母失败，Laya跳过；metadata head为bf63985，但实际pull_request检出 **`69f991ff6348ddcad2411a3b59222683845606b9`**，不能标作bf源码checkout。它不代替独立9ab新WCDF组合。

## 全库存、源码与DA的独立复算

旧API参照是已绿[WCDF组合38153433448](https://github.com/mightyoung/Muyon/actions/runs/38153433448)，精确d76a9683e6e893312941c9159a204117b336c56b，427加载源码。制品11708370994 ZIP SHA256 `1c0fe955f7b052074859ba8572ae30c7dd6253e9a7e4e1d4458151e6cdf924fb`。其API37库存、2446DA/2320hit与既有门禁一致。

新测量八份报告齐全、全部exit0，**428个加载源码SHA256逐Git blob重算**；按不可变9ab树核对八包完整文件名库存、加载/未加载集合、逐DA行身份及未命中集合。每gate的DA fingerprint、逐文件命中与总数均独立重算，测量脚本hash/平台/SDK/八套范围不变。

|package|旧/新源码库存|
|---|---:|
|module_api|37 → 38|
|muyon_ui|27 → 27|
|prototype|11 → 11|
|research|35 → 35|
|supplier_core|81 → 81|
|inquiry|92 → 92|
|host|157 → 157|
|ui_preview|10 → 10|

仅两个加载源码内容变化：新local_export与已改tool_registrar；API导出barrel增加export但无DA。全部其他加载源码的DA身份、未命中集合不变，没有命中数量相同却交换行身份的情况。未加载源码可执行分母仍未知，不称全仓/全包覆盖率。

|API门禁|旧hit/DA|本次完整八套hit/DA|
|---|---:|---:|
|总计|2320/2446|2387/2514|
|tool_registrar|22/26|34/38|
|新增local_export|不存在|55/56|

local_export唯一未命中DA是108行“Format and MIME type are required”异常分支；tool_registrar未命中23/45/49/189。无源码排除、未缩分母或阈值；旧逐文件floor全部保持或提高。models门禁751/778、transfer827/882，完整库存、DA及逐文件命中与旧参照/旧baseline完全相同。

独立本机API-only样本274pass，2041/2514DA；它与作者273pass/2042hit样本及完整八套2387hit分开记录，不拿API-only样本比较完整八套旧floor。

## 明确、有限的门禁修正

仅将`baseline.json.gates[packages/muyon_module_api/lib/]`替换为上述9ab完整八套测量的API gate。其它gate、测量合同、checker和历史顶层快照信息逐字保持，与既有WC-A/typed-payload API局部门禁更新方式一致。**顶层旧source_sha/actions_run_id/package信息仍是历史快照，不能冒称整个JSON改成9ab快照**；本次API gate的完整新来源、制品与复算证据在本报告明确登记。

新API inventory/DA fingerprint不再错配；与旧baseline比较原唯一API drift，与提案比较错误集合为空。更新是对明确产品增量的完整复测后审查，不是自动接受漂移或调低旧标准。恢复所有逆变异后，产品逐字等于固定bf63985；下一步需候选完整绿色CI（含Laya/coverage）与合后CI终态，不以本次红测量直接放行。
