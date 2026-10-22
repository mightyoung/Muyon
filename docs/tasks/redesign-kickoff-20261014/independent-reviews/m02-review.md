# M02 supplier-name 独立非作者只读复审

固定提交 `642a939846a8f87e1fc8872142baa5ab755e1d02`，起点 `421e7332807d0f8a2f7a6a36819601dcad442130`。工作树 `/workspace/Muyon-leader-b-redesign-m02-20261014`。复审只读仓库，产物仅本仓库外目录；没有修改作者分支、M01、原两册/ADR、产品文件或golden。未重复23单元盘点，没有运行模型/设备/真实数据、产品测试或Dart探针。

## 结论

**草案可采纳，C级阻断0；M02完整合同出口尚未闭合。** 两个新增文档精确符合派发范围，17个引用产品文件与固定产品P字节相同。源事实、D目标、M02建议、待定项和not_run清楚分隔。可以据此组织限定合同/离线语义准备，不能登记M03冻结、Rust/双端实现完成或52验收通过。C表示阻断本次草案接收，I表示工程出口前必闭合，M表示表达/fixture补充注意。

## C/I/M与采纳条件

- **C：0。** 未发现将目标冒称现有行为、将字段类别冒称grant、将unknown自动重发或将文档登记冒称运行通过的问题。
- **I-01：名称目标合同仍待冻结。** §4/§8明确raw UTF-16 2000入口兼容策略、Rust trim/NFC/Unicode等价性和同值新意图+1为建议/待定。M02出口前由B与真实合同owner、非作者审查者记录最终名称规范、入口差异选择、错误层、同值新意图是否+1及与同意图replay的区别。不可把草案的“建议继承”直接变golden已批准，也无需重新请求用户决定已定四档或0模型链。跨端差分实际运行归后续对应任务，现阶段不伪报通过。
- **I-02：当前可以派合同，不能冻结编码或实现效果。** D01a最小风险/模式/假传输期限样本、D03a恢复与投影、SPIKE-01双传输及真实Android库加载必须按依赖协调后才冻结M03；wire字段、状态、摘要域及store身份仍由M03唯一源定义。Auto未冻结具体动作是blocked_contract，不能永久confirm；完整旧模式映射和真实分类出口归D01b，不反向阻断所有首片离线合同工作。
- **M-01：旧表单trim差异宜补非法边缘控制字符对照。** §2准确写出领域XML检查发生在trim前，也准确写旧表单先trim，但现有N05未逐入口列出边缘U+000B/U+000C的差异。固定`catalog_form.dart:266`会先`trim()`，Dart SDK `lib/core/string.dart:385`列出trim空白U+0009–000D；故直接领域的`U+000B + 甲`会在`values.dart:52–59`拒绝，旧表单可先裁掉U+000B再把甲交领域。建议M04补这一入口对照，避免后来误认为旧页面所有原始非法字符均由领域原样拒绝。它是旧入口事实补充，非要求改变新领域规范、非本草案阻断；本次未运行探针或复制normalize实现。

## 实际核验的源码事实

17个P固定源码文件及其blob/hash已写入`evidence.json`，每个引用区段实际阅读；没有仅靠作者摘要作结论。

1. `values.dart:43–69`执行String检查→逐rune XML字符合法性→Dart trim→unorm_dart NFC→必需非空→NFC码点长度；`entities.dart:31–33`完整键及name200，`quotation.dart:10–15`路由Supplier。孤立surrogate、U+FFFE/FFFF拒绝；内部合法LF/TAB不折叠。没有UTF-8 bytes/grapheme/NFKC等限制证据。
2. `inquiry_record_tools.dart:143–172`另在规范前检查raw String UTF-16 `.length>2000`，null跳过preflight而完整payload仍拒绝必需name。旧表单`catalog_form.dart:253–266,295–300`重读existing并完整save，没有expected_version；`store.dart:378–395`也没有CAS参数。这与generic显式scope/CAS准确区分。
3. generic handler `inquiry_record_tools.dart:392–409`先`_currentSelection`再查receipt，选中集revision/digest/workspace变化可先scope_changed。`435–460`再查expected_version、完整合并校验与scope，`518–555`写前检查、save和回执同事务，`558–561`外层rollback后转WriteConflict。成功后旧scope再次进入handler可能scope_changed，不等于原效果未发生。
4. `inquiry_write_receipts.dart:36–65`业务身份绑定操作、完整参数、workspace和排序对象身份，scope摘要不含revision/digest，expected_version保留在参数。`tool_registry.dart:967–991`invocation层同身份回放已有结果/无结果interrupted，异身份冲突，不能混称同一幂等层。
5. `inquiry_receipt_lookup.dart:8–59`独立只读查原权威业务回执，无需重走写handler/currentSelection；库文件路径摘要验证、内存库unreadable、notFound/unreadable区分正确。草案将notFound仍视unknown是目标的保守恢复语义，不宣称旧接口结果本身证明没执行。unknown不换UUID/intent/key自动重发，不重新铸grant；旧epoch真EffectReceipt应核对入账。
6. `store.dart:435–438,508–512`同值save仍version+1，日志仅记录变化字段。草案分离这一P事实与新意图+1建议，名称不替代UUID身份；同名两对象不串行，replay不应产生新版本。
7. `inquiry_module.dart:274–300,328–338`supplier.name基础类别none；`host_authorization_policy.dart:13–26`settings只能收紧不供grant。草案正确要求模型实际生成值的声明/输出检查/credential覆盖与当前参数版本合取，再按当前用途和授权判断；字段none不代表授写权或无需输出检查。F03对v1检查/v2提交使旧证据失效。
8. §5及F04确定性完整编辑直Rust，0模型请求/0外发；四正式模式与legacy开关/期限不升权准确沿用D目标。旧review故障confirm的局部事实没有被移植成FullAllow隐形暂停或Auto永久默认。

## 验证范围与M02出口清单

实际命令核对`421→642`仅两个新增文档、`git diff --check`通过、17个源文件P与642字节一致，目标worktree状态为空。A00状态仍14proposed_unfrozen、29not_run，52主验收not_run；文档20个本地fixture行是草案矩阵，未成为新增主验收或通过数。没有运行8套CI或端到端程序，`[skip ci]`不意味着源CI覆盖642。

M02出口须由B记录并独立读回：领域事实/目标差异终态，name规范及入口限值决策，UUID/对象/revision/错误/权限/回执与同值新意图语义，正负fixture与未知项及负责后续任务，首片合同writer/非作者审查者/文件预留。当前非作者文档复审终态可作为其中一项；I-01未闭合的具体case继续blocked_contract。D01a/D03a/SPIKE-01是后续M03冻结条件，不把所有23单元尚无实施writer或全部52用例未实现解释成M02草案不可采纳。
