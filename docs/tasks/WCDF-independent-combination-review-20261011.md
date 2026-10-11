# WC-D-F：合后完整性补修独立组合复验

固定作者源 `7ad4c81e22ab1e9ba297e03d12f5c51978cc3e98`，RED `8b2d551c72186f34b3848b0b996be873d01c9eae`，fix `0676c78499f8c78a2c61af953be2f5a45d46c7b5`。源基于旧 develop `140a1b305271ca6a753bf6d2fd99f6b9c0e7c044`；本次独立组合最新 develop `330020c07af3431047ceefc05f76b1b5abc332ba`（已含 RS1）与作者固定源。作者产品改动仅 `inquiry_receipt_lookup.dart` +46；原作者测试+201及任务说明保留。组合候选 **`d76a9683e6e893312941c9159a204117b336c56b`**，审查分支 `review/wcdf-independent-20261011`。作者分支与产品未改；额外23测试与一处任务格式更正由独立审查提交 `433ebc9c0d4d626f1690889eecefdb9bf5f47ea8` 加入。

这补修已合 PR50 的 CR16 I1/I2，不回退既有集成；旧绿色 CI 不能否定后发现的缺口。用户正式交付并授权优先合入，作者交付等待已解除。Parent静态首轮确认核心修复与真实scopeKey兼容、未见写路径；要求补的结构矩阵/UUID/原始摘要/重开检查均独立复跑通过，无真实兼容回归。

## 实现与兼容边界

读 WC-D-F、CR16、REVIEW/invariants 与现写端。create 结果必须经既有 `requireUuid` 小写 UUID v4/正确 variant 校验；create/update 的 values 为 Map，delete 的 referencing_records 为 List；这些历史结构检查在身份比对前执行，错形为 unreadable。只读 lookup 不重执行写工具、不读当前对象重建历史状态、不写领域/宿主库、不签审批或触发通知。

**任务原描述错误已修正文档，旧序列化未改。** 双向核对 `GenericWriteIdentity.scopeKey` 写端与 `_checkStoredScope` 查核端：scope 是 JSON 对象，恰含 workspace（String/null）与 objects（List）；objects 每项是 JSON **字符串**，再次解码为 `[moduleId, objectType, objectId, nativeProjectId]`，前三项 String，第四项 String/null。写端对字符串排序，查核不排序/重编码存储字符串。requestDigest 与 scopeDigest 始终分别用原 arguments 与原 scope 字节计算。

这些新增检查不是对全部历史请求字段的完整语义校验；范围按 I1/I2/N1 明确合同。不把与当前结构兼容说成所有未来 scope schema 均兼容。

## 独立实际复跑

官方 Flutter3.47.5/Dart3.13.4、Linux，目标测试通过前无需改变任何产品逻辑。SDK 缓存/生成配置均未提交。

- 作者原目标：54pass/0skip/0fail。
- 临时替换唯一查核产品文件为固定 RED 字节（作者测试仍完整），编译启动正常：**42pass/12fail**。第一 I1 失败为 `a create receipt whose result id is not a lowercase UUID is unreadable [E]`；I2 从 create values removed 开始；scope empty object/object item not tuple 也失败。N1 的正常只读路径在旧代码已通过，不伪称本次 RED 有 N1 行为失败。不是12项清理超时连锁。
- 独立补23项后的目标：**77pass/0skip/0fail**；四种 create/update/delete/restore 存储回执在非空 workspace/nativeProjectId 格式下跨宿主关闭重开 matched。域结果来自真实提交；非空两值的历史 request 用实际未改的旧 encoder 重建并存储，是兼容夹具，**不声称当前解析器在真实写入口产生这些合成 ID**。
- scope.objects null/Map、workspace number、对象 Map 非 JSON字符串、tuple长3/5、前三槽每槽 null/number、第四槽 number，共13个错形，即使提供对应新 raw digest 也 unreadable/false/null。
- 大写 UUID、version1、错误variant、周围空白四项拒绝，与 requireUuid 的既有规则一致；真实 writer 产生的 ID 通过同一规则，newUuid明确设 v4/variant bits 并输出小写。
- arguments 与 scope 的空白/键序变化，两项都使旧 query identityConflict；对应新原始字节 digest query matched，证明未为摘要重编码。
- 原 runtime 四状态 matched/identityConflict/notFound/unreadable，逐路径领域/宿主 total_changes 不变，AppState监听0，领域行数/版本不变。
- module_api全量 **250pass/0skip/0fail**；inquiry_module 经宿主 cwd 全量 **302pass/47skip/0fail**；宿主 strict analyze No issues found。

作者 Mac inquiry16fail 的原始平台归因未重建，不能直接采信「基线也失败」。本次 Linux 全量302/47通过，无新增skip/超时/基线或 golden 更新；固定组合完整 CI 的宿主与各包终态另列。

## 临时逆变异：恢复产品后报告

| 逆变异 | 实际结果 |
|---|---|
| 删除 create 两 UUID 校验 | 53pass/1fail，真实非法 create ID 被当matched |
| 删除 create/update values 校验块 | 48pass/6fail，缺失/null/String 被当 identityConflict |
| runtime matched 后 state.changed() | 53pass/1fail，监听实际1而期望0 |
| 删除整个 scope 校验调用，独立23子集 | 10pass/13fail，完整错形矩阵均被当matched |
| 摘要前 canonicalJson 重编码原 args/scope，独立23子集 | 21pass/2fail，原始字节身份断言失败 |

全部编译/启动正常，抓业务断言；产品逐字恢复为固定源。临时原始日志/脚本不入仓库。补测断言不放宽、无跳过。

## 固定 SHA CI

作者 [38150396629](https://github.com/mightyoung/Muyon/actions/runs/38150396629) completed/success，2026-10-11 15:32:23 UTC；metadata与原始checkout精确7ad4c81e完整SHA。3555pass/207skip/0fail，旧基线research231/host1840；不替代本次新组合。

本次[组合38153433448](https://github.com/mightyoung/Muyon/actions/runs/38153433448)，精确d76a9683e6e893312941c9159a204117b336c56b：completed/success，终态2026-10-11T16:16:04Z；原始checkout与metadata精确上述完整d76 SHA，8包analyze/8套测试、doctor23、Laya、coverage与制品步骤均success；3608pass/207skip/0fail。

|suite|pass|skip|fail|
|---|---:|---:|---:|
|module_api|250|0|0|
|muyon_ui|380|152|0|
|prototype|39|1|0|
|research|236|0|0|
|supplier_core|498|4|0|
|host|1888|3|0|
|ui_preview|15|0|0|
|inquiry|302|47|0|

## 交接与放行条件

同时核固定第6次交接 `ae4fff1b47967a4ceb5ca8935df180d521370d80`（只加44文档行），保留完整历史，在新快照另注当前状态：LE01两个Important仍阻断；Mac失败是作者报告；PR50 base保持原作者任务分支，不改base或自动关单来代替验证。ADR0001原有两条仅记 A 派发/B集成，本次补用户最新完整职责接替一条，未重复旧决定。

本报告后继仅文档，无独立完整CI；可执行证据固定上述d76组合。Parent静态首轮未见阻断，聚焦补测和五逆变异已通过；完整新组合CI成功，远端 develop 与固定源复核不漂移后可按用户授权正常 no-ff 合入；合后再核精确新develop完整SHA与独立CI终态。main、作者及审查分支保留；不部署、强推、删分支、回退，未调用真实模型/Android，未导出MUYON_EVAL_REAL。LE01补修bf63985a766f39912a53661bc63e37caa430ab7b已正式交付，Parent静态原两I闭合；独立三公开复现与七变异已复跑，最终仍待另批完整八套及覆盖率分母/旧floor复核，不随本批合入。SN6仍待交且须AIUI整链CR18统一外审。

RS1已先闭环：develop330020c07af3431047ceefc05f76b1b5abc332ba的[合后38152607452](https://github.com/mightyoung/Muyon/actions/runs/38152607452) completed/success（16:00:16 UTC），原始checkout精确全SHA，3569pass/207skip/0fail；8分析/8测试、doctor23、Laya、coverage全通过。第6次交接的330基线经独立确认，未用旧fc9覆盖。
