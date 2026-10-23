# U1 固定 Contracts 候选消费与测试设计

历史准备文档，后续实际实施见REPORT。用户已批准最小工具安装并完成；当前codec/模型/校验纯JVM已有RED/GREEN，不能沿用旧codeStatus=absent或工具阻断描述作为最新状态。完整项目/Android及可信ref解析仍受阻。本稿不定义另一套共享 types，不复制 JSON fixture，不改 Contracts 登记文件，不启用 renderer 或业务动作。

## 固定输入

| 输入 | 完整 SHA / 路径 | 使用边界 |
| --- | --- | --- |
| 最新 develop / 本隔离分支起点 | `fd26dcdabcdac996bc2881e8141cac2b519966fc` | 2026-10-23 重 fetch；Contracts 尚未合入 |
| 已批准 U0–U3 计划/总索引/设计 | `64900d4a6a46a9ef2919bcf922fb059413b1ce82`，docs/superpowers/plans/2026-10-23-intelligent-ui.md、docs/superpowers/plans/2026-10-23-public-services-index.md；docs/superpowers/specs/2026-10-23-public-services-ui-design.md | U1 纯模型与校验；具体外观 U0 未认可，U2/U3不开始 |
| C1 公共值 | `6e7f774b1559a0a9693eeb195ba13c9ded561993`，crates/muyon-core/src/services/types.rs | 已固定候选，不是 develop；Revision/Scope 仍复用既有 contract，DocumentRef 复用 documents/identity.rs |
| C2 原回执 | `b626c18a5dff184519e59bb866e5ed37362ac84e`，services/commands.rs | 只读理解边界；不在 U1 实现 dispatch/账本/取消 |
| C3 最终源码 | `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`，services/drafts.rs | 只读理解草稿确认/恢复；不是 U1 提前实现 U2 |
| 最终证据封套 | `4d49a580cb518d9b0b80c9df3df1ff564194a639`，docs/tasks/public-v02-C1/C2/C3/REPORT.md | 三份已完整读取；上游619次测试/Clippy是其报告，不是本环境复跑 |
| U0 具体候选 | `98aed744ab1b920cea4575115a64d1e2223ade2a`，docs/design/public-services-v02/ | 已交文档，visual draft；不延续被否决外观 |

本隔离分支 `task/publicui-u1-preparation-20261023` 从最新 develop 建立，没有把未合候选整体 merge/cherry-pick，也未动旧 U0 分支。上游通过 git show 固定读取，后续测试 runner 按显式受信 fixture 根及摘要消费，不能悄悄取变化分支或本地另一任务 HEAD。Contracts owner 独占 services/mod.rs、core lib.rs、FFI lib.rs。

## 共享 fixture 事实定义与逐例适配目标

三个文件在同一根 `docs/contracts/public-services-v02/fixtures/`，均读取最终证据 SHA。types.json 与 C1 原提交逐字节一致。下列是读取清单，不是新样本或 Kotlin 已通过结果。

| 文件 | SHA256 | 本轮实际静态结果 |
| --- | --- | --- |
| types.json | `af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5` | contract_major/schema_major=1/1；8 cases、6 legacy_identity_vectors |
| commands.json | `9f7618861e7fbc33c82e53d06c2acefb06e9fe3e40129eb172085cb48d104adc` | JSON可读；6 lookup_cases；U1不实现此原owner协议 |
| drafts.json | `e1012c72cccea844a65a66e3b4a7ce3ae3a5257bba476f98ee9b4983cefd1460` | JSON可读；draft/ack/lease正样本；不宣称已有草稿反例集 |

| types.json 真实 case id / kind | 固定预期 | U1 codec 测试将验证 |
| --- | --- | --- |
| scope-exact / scope | valid=true | scope_generation“9007199254740993”逐字保存；account_id=null不填默认账户 |
| scope-no-self-approval / scope | valid=false | approved字段拒绝，不能建可信scope或授权 |
| result-root / result | valid=true | input_document_ref、revision、直接上游集合和digest保持expected；可解码不等于来源可访问 |
| result-empty-id / result | valid=false | result_id空串拒绝 |
| result-unknown-authority / result | valid=false | grant字段拒绝，解码不能签发权限 |
| coverage-unknown / coverage | valid=true | processed“0”、total=null、unknown同时保留，不造0%或完成 |
| coverage-complete / coverage | valid=true | processed/total均“2”、failed_units空；只读显示该事实 |
| error-preserves-unknown / error | valid=true | unknown_outcome/after_lookup/unknown/original:1保持，phase原字串不作派发证明 |

六个真实 legacy id：ffi-intent-format、ffi-plan-format、ascii-128、ascii-129、utf8-129、public-value-is-not-native-authority。未来 Kotlin runner 仅执行公共值解析并比较明确存在的 valid_public；valid_native 是原 Rust 命令校验的上游预期元数据，不在 Kotlin 重建第二个原命令校验器，也不把它当授权。需核 native 行为时调用原 owner 测试/可信桥另验，不能用纯 JVM 结果替代。ffi-plan-format 没有 valid_public，仅核元数据/字节长度，不补默认true。公共不透明值与原命令身份校验不同，不能把公开“甲”可解析误作原命令可以执行。Kotlin校验 byte_length 要用UTF-8，不用String.length。

拒绝未知kind、未知vector field或缺必要valid/expected元数据，不能跳过样本计作通过；运行时报告实际消费ID集合与计数。该规则是测试完整性，不另建产品授权或类型注册。

## 原始 wire 与 codec 检查点

以下依据固定 Rust 源及现有 contract.rs，不凭接口名字猜规则。这些约束后续已部分实施验证；具体固定source、计数和未验范围以REPORT为准。

| 项目 | 现有真源 / 测试设计 |
| --- | --- |
| Revision | contract::Revision，ASCII十进制0..u64::MAX，无多余前导零；Kotlin仅字符长度/词典检查，保留原String，不经Long/Double；0、9007199254740993、9223372036854775808、18446744073709551615正向；空/-0/+1/01/小数/指数/全角数字/超界反向 |
| UnixMs | C1 UnixMs，为规范i64字符串；0/-1/两端正向；-0/+1/01/空白/超界及JSON number拒绝；Kotlin同样保留String |
| ResultId/JobId/IntentId | 非空、<=128 UTF-8字节、无NUL；不是原ASCII命令身份规则。不擅自trim、限制成UUID或据解析建立命令 |
| Digest | 64位小写ASCII hex；uppercase/63字节/非hex拒绝；不拿展示文本临时计算权威digest |
| DocumentRef | 既有documents/identity.rs构造验证workspace/project/document身份，不等同宽松公共opaque；ScopeRef本身仅解码shape。codec保持嵌套结构及source语义，不将两者校验混用 |
| Coverage | processed/total是JSON字符串且合法u64；processed>total拒绝；complete须total=processed且无failed_units；unknown total=null不是0；failed_units为u32范围数字 |
| ServiceError | exact snake_case字段及枚举来自C1；phase当前String，Money/Quantity/phase新规范均未冻结；保持phase原文，不自造enum/decimal parser，不从host_call推not_started |
| 严格 JSON | Rust先用contract::decode_json查重，再typed decode；重复字段（含嵌套）必须在JSONObject/Map覆盖前拒绝。未知安全字段/错类型/不兼容major拒绝；原transport上限1048576字节与UI文本65536字节是不同限制 |

org.json 具体缓存版本、编译classpath与重复key行为尚未在本环境验证；不得默认“JSONObject会处理”然后丢失重复键证据。后续用现有缓存与已审代码实现，不新增JSON依赖；若现有API不能保留必要信息，先提出最小实现/测试，不能弱化拒绝规则。

## UIPlan 专属校验的后续 RED 顺序

这些是已批准 U1 测试场景；不属于目前 C1 fixture 的字段，不将测试名字或伪造JSON当共享合同。下列是准备时的执行顺序；后续实际已写测试并取得纯JVM结果，详见REPORT；未运行部分不补填PASS。

1. 工具到位后，先建立计划指定 T/PlanValidationChecks.kt 与无下载run-offline.sh；T为 app/src/test/kotlin/com/mightyoung/muyon/product/ui/publicservices。先校验编译器、JDK及实际org.json缓存；只编译相应P源码和T检查，缺前置即退出BLOCKED。
2. 如新API不存在，结构RED单列；仅为目标校验加最小明确unavailable桩，再观察具体行为断言失败，固定RED source SHA和原始日志，禁止仅拿“符号缺失”作TDD证据。
3. 共享codec先消费上述C1原fixture全部ID，拒绝篡改/错摘要/不匹配major；有效expected按JSON结构比较但所有十进制仍String，不能依赖对象key顺序或浮点相等。
4. planSafetyChecks：未知component/action、approved字段、snapshot修订不符、缺source→TextOnly；fake command计数=0，原答仍由独立AnswerRef读取。
5. 图/规模边界：256/257节点、16/17层、32/33 children、65536/65537 UTF-8文本字节、重复id/环/悬空children；明确根深度计数并在正反配对样本中固定，不能只有一个超界负例。
6. 十族Props配对/封闭字段校验：Form字段key/类型和值/错误关联，ResultList三列长度/唯一ID/同位source，claimRelation/saveStatus白名单；确认和回执只能持可信ref，模型自报approved/saved/complete不获信。
7. revisionAndPageChecks：大数精确/不映射旧Long，旧page1→0/旧page<=0拒绝、多字节区间按UTF-8半开范围；ValidatedPlan内部构造与集合不可变副本需实际测试调用方后续修改不影响已验证值。
8. GREEN后跑原cards/run-offline.sh回归，全部记录实际source/命令/计数；U1只模型/codec/validator，renderer、UiEvent投影、Accepted调度、UI外观仍不进入本片。

## 不填补的共享 fixture 缺口

C1当前没有 PresentationRequest/UIPlan/SourceBinding/SourceLocator/pageIndex/UTF-8区间样本；result-root不是text source fixture，content_digest不能自动等同textDigest，也不证明原文可读。U1的SourceBinding必须由宿主sources字典在当前snapshot/scope下解析，不将C1 ResultRef任意扁平化成来源事实。若跨语言需要新增来源/呈现共享样本，向Contracts及Documents owner提出变更，由其固定版本后消费；本片不另复制一套共享定义。

C2 commands fixture仅lookup形状，不含完整准备/成功/取消场景。C2源码保留 execution_status 与 cancellation_requested，两种CancelRequested视图仍须区分原Pending/Unknown；C3正确SaveAck也仅草稿确认，不能让U1据模型saveStatus显示可信已保存。以上用于保持U1边界，后续U2实现另等依赖与外观gate。

固定Contracts已获父任务授权作为候选消费，但B独审/CI/合入仍未完成。上游候选变化后先对固定SHA/fixture摘要核对，不自动跟分支走；未冻结Money/Quantity/phase及结果ID转换不在本设计新增实现。
