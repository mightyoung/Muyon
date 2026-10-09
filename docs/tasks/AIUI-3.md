# AIUI-3 本地公式登记与版本化重算（任务书草案）

状态：**任务书草案，待唯一集成负责人审查**。用户已授权并行推进开发；纯公式片可按派发范围推进，涉及正式契约变更的能力仍须先采纳建议。本次文档交付不写产品实现，仅推独立文档分支，不合 develop。
建议分支：`task/aiui-3-local-formulas`（执行前重新检查远端占用）。
依据：AI 原生界面方案 §5.3；AIUI-1 `276b29146d3eb902380cceac708209cc6ef344c0` 的 `aiui-stream/1` §1/§5；初始 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc` 的现有业务计算；GROK-7 `18ae5127474d6841ad331ca2251076ecca431a81` `docs/reviews/2026-10-09-research-walkthrough.md` §4。
GROK-7 §0 旧汇总写 8，但 §4 逐项表与 §6 均为 **9**；本任务按逐项 9 条登记需求，不复制旧汇总数字。

## 目标与边界

把宿主可信事实和用户已声明的界面输入交给有限的公式登记表，产生现有 `ComputedValue`，本地重算不依赖模型。先交付 scalar 核心与询价计算一致性，再按宿主投影依赖扩展科研；不能把尚无事实输入的科研/阶梯项写成已接通。

复用 `BindingRef`、`DataSnapshot`、`ComputedValue`、`UiSessionState` 和 supplier_core 已有计算；不新造状态运行时，不改流协议，不放宽 scalar 校验，不接业务写入，不接付费模型，不引入第三方包。AIUI-5 负责模型提示、集合 codec、组件 adapter 和流接线；AIUI-7 / REG-3 负责科研可信事实生产，AIUI-6 负责询价场景。公式不得写数据库、发网络请求或产生授权。

**禁止**接收模型提供的 formula / expr / value、任意表达式或脚本。模型只引用宿主已经算好的 `computed:id`；即使将来模型选择公式名和输入引用，也须由宿主许可表检查后开新规划会话，不能改变 aiui-stream/1 的输入边界。

## 已有代码与应保持的业务规则

下列证据均在初始 develop 完整 SHA `01404ae472451f55af5baa6ce76c95af72b0cbfc`，不是未合分支已存在于主线的声明。

- `packages/muyon_module_api/lib/src/ui/snapshot.dart:56-69`：ComputedValue 只有 value / inputVersion / computationId，没有公式注册、单位或错误状态字段；本任务不得假定现成 registry 方法。
- `packages/muyon_module_api/lib/src/ui/state.dart:29-55,65-77`：resolve 只读同版本 computations，edit 更新本地状态及 draftRevision；现有快照 computations 不会自动随用户 edit 重算，须显式连接宿主计算调度，不复制 UiSessionState。
- `packages/supplier_core/lib/src/pricing.dart:1-30`：十进制文本转百万分整数；`roundedDivide` 最近整数、半值远离零，`multiply` 使用该舍入。原函数不是输入校验器：边界先用 domain 允许的格式验证，禁止以 `micros` 的宽松解析替代字段校验。
- 同文件:40-58,77-101,103-150：`priceInUnit` 合并单位/税转换后一次舍入；`atQuantity` 使用达到的最高阶梯、成交价不再应用阶梯、不可换单位保持原报价；`priceInTaxMode` 缺税率仅同税口径可接受，跨币种不支持，不明税口径返回 null。
- `packages/supplier_core/lib/src/budget.dart:65-80`：真实附加成本 API 是 **effectivePriceOf**，额外成本按需求数量摊分；无附加成本、缺数量或数量零返回单价。不得发明 `priceWithExtra` 已有方法。
- 同文件:242-294：预算先按加价率算每行单位销售价，再按数量算行总价，再求和；显式 unit_price 覆盖加价计算；`Budget.margin = price - cost` 是**毛利金额**，不是毛利率。不得改变舍入次序，不把 margin 误显示为百分比。
- `packages/research_module/lib/src/app/workbench_app.dart:1195-1265`：比较卡只比较同任务修订，按指标键展示原值，保留“不自动判断优劣或科学有效性”；尚无 delta/pct 业务函数。`:1258-1259` 用 artifacts List 长度（null 为0），非 List 非 null 可能抛类型错误，新的投影须验证畸形类型并保留诊断，不伪称已有代码安全吞掉所有畸形数据。

## 宿主计算接口草案（待 owner 采纳，不是假定已有 API）

建议新文件 `apps/muyon/lib/platform/ui_formula_registry.dart`，新测试 `apps/muyon/test/ui_formula_registry_test.dart`；纯通用定义如有必要放 module_api，但 module_api 不反向依赖 supplier_core / research_module。可以使用不同路径，回报时记录实际路径与原因。

接口建议（仅新宿主侧文件，不反向改变正式UI类型）：`UiFormulaRegistry.evaluate(UiFormulaInvocation invocation, DataSnapshot snapshot, Map<String, Object?> currentUiState) -> UiFormulaEvaluation`，同步纯计算，无IO。`UiFormulaInvocation`含`formulaId:String`、`formulaVersion:int`、`computationId:String`、`inputs:Map<String,BindingRef>`；`UiFormulaEvaluation`含`status`、`value:Object?`、`unit:String?`、`inputVersion:SnapshotRef`、`computationId:String`、`inputFingerprint:String`及`errors:List<String>`。registry由宿主构造不可变定义表，`currentUiState`是完整冻结投影且只允许预声明键；结果转换为ComputedValue及快照发布由AIUI-5负责。输入fingerprint建议为按slot排序的kind/id/typed值与来源版本的确定序列摘要，不与业务draftRevision混用；格式采纳后有canonicalization测试。定义不一致或缺元数据直接拒绝，不猜单位。

登记项应含：固定名称和版本、固定输入槽名/类型/单位、允许 BindingKind、输出类型/单位、执行函数。计算请求由**宿主**建立：computationId + 登记名 + 槽名到 BindingRef 的映射；它不是流行格式。用户不能用编辑输入改登记名、输入键集合、币种/对象身份等宿主元数据。

1. 首批输入仅 fact / uiState 引用；事实必须存在且对象/字段身份有效，用户状态键必须由 snapshot.initialUiState 预声明，由宿主用现有 session.resolve 冻结当前值后交纯 evaluator。禁止原始字面值、sourceSpan、任意路径查询、模型对象以及递归 computed 依赖；需要依赖 computed 的 DAG 留后续正式契约。
2. 区分 registry 固定名称/版本（formulaId）与宿主某次实例稳定 id（computationId）；两者不能互相冒充。
3. 金额/数量/百分数用校验过的 decimal String；数值科研指标用 finite num。单位、币种、税口径、指标单位/同修订身份由宿主 fact 和登记许可提供，不从模型文案猜测。输出金额保持 canonical decimal String（最多6位小数），科研数值为 finite num，计数为 int；scalar 规则保持。
4. 推荐宿主侧结果带状态 `ready / unavailable / invalid / stale` 和稳定错误码，**不直接修改 ComputedValue 正式类型**。ready 才写入 ComputedValue；合法但不可计算（缺值/零分母/不可换币种）允许明确的 null ComputedValue 并在旁路诊断注明原因；invalid/stale 不发布为有效新结果。不要把错误对象当 scalar，也不要用0冒充缺值。
5. `inputVersion` 绑定本次 snapshot.ref，computationId 是宿主声明的稳定实例 id。**现有 runtime 不支持自动重算/换快照**：UiSessionState.snapshot 是 final，resolve(computed) 只读 snapshot.computations；UiSurfaceController.acceptPlan 要求相同 snapshot/intent/catalog identity。AIUI-3 只提供纯 registry/evaluator 和宿主声明实例、依赖引用，fact 版本和当前 typed state fingerprint 必须作为宿主计算依据显式记录（fingerprint 格式是待 owner 采纳建议，不更改正式 ComputedValue）。fact 或用户参数变化后的 immutable snapshot 新 revision、重校验、controller 刷新/草稿焦点保留钩子交 **AIUI-5 复用扩展唯一 runtime**；不能沿用旧 inputVersion 或旧 ValidatedUiPlan/operation 授权能力。snapshot.copyWith 现有仅支持 computations/sourceDigests，不假定它能更新initialUiState。API state/validation/plan/workspace及现有controller文件由AIUI-5独占，本任务不改。
6. 拒绝 unknown formula / unknown slot / unknown ref / wrong kind / wrong type / unit mismatch / nonfinite / oversized input；用户字段格式不合法保留用户草稿并降级，不能回写成0。事实状态 readFailed/conflict/notDisclosed 不当可信数值；unverified 可以计算但宿主保留来源与未核验标记，不能升级成 verified。
7. collection 项只接受宿主已验证的有限投影：首批可由宿主选定固定 scalar 引用组；集合/行/项 codec 未采纳前，不接 List/Map 快照绑定、不接受 JSON 字符串伪装集合、不把列表下标当业务对象。推荐待采纳初版上限：单实例32输入槽、单decimal字符串256 UTF-8字节、单实例输入16 KiB；统一常量测试31/32/33槽、255/256/257字节及总字节边界。现有领域格式/精度/正负规则优先，不能因为低于该上限就接受原业务非法输入。

## 首批必须交付（scalar；加价helper作为明确外部依赖）

下列名称均为建议登记名，待采纳后固定版本；示例只用于测试夹具，产品数字仍来自绑定。`F.*` 是 fact 槽，`S.*` 是预声明用户状态槽，不能以这些名字默认创建输入。

| 名称 | 输入引用/单位 | 输出/示例 | 实现依据与新增 test 名及断言 |
|---|---|---|---|
| `ui.sum_decimal` | 宿主固定的 F.amount1…N，同币种/单位 decimal String；N由宿主登记，不由模型传集合 | canonical同单位 String；0.1+0.2→`0.3`；空组仅宿主显式允许时→`0` | 复用 micros/fromMicros 累加，不用double；`sum_decimal_exact_and_unit_checked` 断言0.3、币种混合invalid、缺项unavailable而非跳过 |
| `ui.product_decimal` | 两个 F/S decimal 槽；宿主登记量纲组合，例如 数量件 × CNY/件 | canonical String；3 × 0.1→`0.3`；0.000001×0.5→`0.000001` | 复用 multiply；`product_decimal_rounds_once` 断言半值微量舍入、单位错误invalid、合法0产生0；一般负数许可由owner定，询价数量不擅自允许负数 |
| `inquiry.tax_price` | F.price、F.currency、F.tax_mode、F.tax_rate、F.deal_price（允许null），宿主允许的S.target_tax_mode；金额CNY/报价单位，税率为百分数13而非0.13 | excluded100+13%→`113`；included1÷1.13→`0.884956` | 从校验过的scalar facts组装宿主quote，调用priceInTaxMode；`tax_price_matches_supplier_core` 断言同税口径缺税率保留原值、转换缺税率/null、不明口径/null、跨币种/null、0.000001+50%→0.000002 |
| `inquiry.markup_unit_price` | F.unit_cost、S.markup_rate（百分数12.5）、F.explicit_unit_price（允许null）；同币种/单位 | 0.1加12.5%→`0.1125`；10.333333→`11.625`；显式单价6→`6` | budget内现有计算无独立公开helper；如需提取共享纯helper并令budget使用它，交supplier_core owner单独依赖修复，必须证明行为不变；AIUI-3不并行改budget；`markup_preview_matches_budget_unit_price` 将同夹具preview和Store.budget结果逐项相等，禁止另抄公式漂移 |
| `inquiry.margin_amount` | F/S销售额和成本，同币种；输入来自宿主按现有预算逐行先舍入后求和的输出事实 | 金额String；29.5875−25.966666→`3.620834` | 精确整数减法复用微量；`margin_is_amount_not_percentage` 断言例值、单位是CNY非%、负毛利不截成0、缺值unavailable |

`inquiry.markup_unit_price` 共享helper提取仅限现有计算去重，由supplier_core owner负责；helper未就绪时可以交付宿主已算好budget.unitPrice的引用登记/对照夹具，必须标记参数预览计算待依赖，不自行复制budget公式。求和、乘积用于展示不是替代整个 Store.budget，不绕过报价有效期、停用供应商、最低量、正式报价等已有筛选。

## 后续依赖项（预留名称/验收，条件满足后实现）

### 询价阶梯与单位/附加成本

| 名称 | 输入/输出/单位/例值 | 前置与新增test/assert |
|---|---|---|
| `inquiry.quantity_tier_price` | 宿主quote/product身份与版本；S.qty decimal、F.unit、F.price/F.deal_price及宿主已验证tiers；同币种单位价；阈值10→90、50→80.5，5→100 | 阶梯集合宿主投影/codec归AIUI-5、事实生产归AIUI-6；调用atQuantity，`tier_price_matches_at_quantity` 断言恰好阈值、成交价锁定、不改quote、不可换单位无阶梯且保留降级诊断 |
| `inquiry.unit_tax_price` | quote与product宿主单位转换表、目标unit/currency/tax_mode；同金额/目标单位价 | 单位映射可信投影前置；调用priceInUnit；`unit_tax_price_single_rounding` 对照现有unit_conversion_test，不先round税再除单位 |
| `inquiry.effective_unit_price` | 宿主归一化F.unit_price/F.extra_cost，S.qty；金额/单位；100+50/2→125 | 调用effectivePriceOf；`effective_price_keeps_existing_zero_qty_rule` 断言数量0/缺失均原单价，无额外成本原单价，负数/坏格式invalid，不改业务函数零值规则 |

### 科研 9 条需求完整映射

科研计数不是从project/run id由公式偷偷查询数据库：AIUI-7先在正确项目/对象/任务修订范围内投影事实，registry只读传入引用。集合返回值不能直接发布到scalar computations。以下新增 test 全部建议放 `apps/muyon/test/ui_formula_registry_research_test.dart`；该文件目前不存在。

| 名称 | 事实/用户输入与输出单位 | 示例及test/assert；前置 |
|---|---|---|
| `research.entry_count_by_kind` | 同project entries.kind的宿主有限投影；S.kind白名单；int条 | papers,papers,claims选papers→2；`entry_count_respects_project_kind` 断言另一项目排除、空集合0、unknown kind invalid；投影AIUI-7/codec AIUI-5 |
| `research.task_count` | 同project当前task heads投影；int个 | id A r1/r2 与 B r1→2；`task_count_uses_latest_heads` 断言按store.tasks头查询不数历史revision；投影AIUI-7 |
| `research.artifact_count` | 所选run经宿主确认的artifacts长度 scalar fact；int个 | 3产物→3；缺artifacts→0；`artifact_count_distinguishes_missing_and_malformed` 断言畸形非List数据invalid诊断，不把读取失败当0；长度投影AIUI-7（直接fact展示优先，不强造无意义公式） |
| `research.run_metric_delta` | F.metric_a/F.metric_b finite num；F.task_id/revision一致、宿主相同metric key/unit；S.metric_key仅选宿主已投影槽 | 0.81−0.75→约0.06，同指标单位；`run_metric_delta_checks_revision_units` 用closeTo，非finite/非数/null→null诊断，跨任务/修订/不同单位invalid；不判断优劣；scalar投影后可先实现 |
| `research.run_metric_pct_change` | 与delta相同，基准b固定；finite num或null，无量纲ratio | 0.81/0.75基准差→约0.08，不能输出8冒充ratio；`run_metric_ratio_zero_is_unavailable` 断言b=0→null、非finite→null、(-1−(-2))/(-2)→-0.5（若owner采纳允许负基准），保留正反方向；scalar投影后可先实现 |
| `research.evidence_count_for_section` | 同project/section的outline引用投影；int条 | section A两行、B一行→A=2；`evidence_count_respects_section` 空节0、其他项目排除、读取失败unavailable；投影AIUI-7 |
| `research.section_support_counts` | 同project sections.support有限投影；建议每个合法support独立scalar计算id，单位段 | supporting两节、inconclusive一节→对应2/1；`support_counts_publish_scalars_only` 断言全部枚举含0、未知support诊断、不发布Map；GROK7建议对象输出与scalar契约冲突，等待owner选分槽/正式codec，AIUI-5+7前置 |
| `research.accepted_run_count` | 同project runs accepted布尔投影；int次 | true,false,true→2；`accepted_count_is_not_validity` 断言仅accepted计数、不过滤/推断科学有效性、不把status completed当accepted；投影AIUI-7 |
| `research.claim_link_count` | paper/claim稳定id+rev、宿主按RelationsPage生成的显式边投影；S.direction仅from_paper/from_claim；int条 | 明确两条边→2，标题相似无边→0；`claim_link_count_uses_explicit_revision_edges` 断言id/rev与方向、跨项目隔离；边去重/多版本口径先owner采纳，AIUI-7投影，不造模糊标题链接 |

## 待 owner 采纳的规则（不擅自决定）

1. 通用decimal负数/小数位上限与输入长度：询价现有字段验证继续生效，通用公式额外可接受范围须单列；不能借新公式放宽domain字段。
2. “毛利率”是否以售价为分母或成本为分母、显示百分数位数：**不在首批登记**，已有 margin 是金额。若新增 margin_rate，明确分母、0的null、单位ratio与显示%的边界后另验收。
3. 科研差值/比例是否保留finite double（推荐保持原指标精度，只在展示层舍入）、负基准是否接受（GROK7定义建议接受非零有限基准）；不套询价六位十进制规则到实验指标。
4. section_support_counts用多个scalar还是正式集合codec、claim_link_count边重复与rev计数口径、snapshot参数变更revision allocator：先契约owner确认，再实现对应项，禁止临时JSON字符串蒙混过validator。

## 验证与交付

新增核心 `apps/muyon/test/ui_formula_registry_test.dart` 包含上述首批5项正反用例，以及 `unknown_formula_rejected`、`model_literal_expr_value_rejected`、`undeclared_state_rejected`、`wrong_binding_kind_rejected`、`nonfinite_output_rejected`、`input_limit_boundary`、`stale_input_version_not_published`、`same_snapshot_changed_state_fingerprint_rejects_cached_result`、`evaluation_does_not_mutate_state`；其中fingerprint规则待owner采纳。AIUI-5独立验收 `edit_recomputes_new_snapshot_revision`、`invalid_edit_preserves_user_draft`、`restore_recomputes_without_business_effect`。断言实际computed值/错误码/版本/原事实未变，不仅断言“无抛异常”。新科研/询价后续用例以本表test名执行，缺投影依赖明确未实现，不用skip冒充交付。

现有必须保留通过：
- `packages/supplier_core/test/pricing_test.dart`：`tax conversion rounds exact decimals and refuses unknown bases`、`price tiers: the largest step the quantity reaches sets the price`、`extra cost spreads over the quantity needed`。
- `packages/supplier_core/test/unit_conversion_test.dart`：`combined rounding does not round tax before dividing units`；验证单位与税合并舍入。
- `packages/supplier_core/test/store_test.dart`：`totals are exact and grouped by category with markup`；25.966666/29.5875/3.620834 与显式单价保持。
- `packages/research_module/test/run_comparison_test.dart`：`only runs of the same task revision appear in one comparison`；不得因公式把不同修订混入。

建议命令（执行实施后，路径以实际交付为准；云端SDK不可用时走冻结SHA CI并写未本地运行）：
```sh
(cd apps/muyon && flutter analyze && flutter test test/ui_formula_registry_test.dart)
(cd apps/muyon && flutter test test/ui_formula_registry_research_test.dart)
(cd packages/supplier_core && flutter analyze && flutter test test/pricing_test.dart test/unit_conversion_test.dart test/store_test.dart)
(cd packages/research_module && flutter test test/run_comparison_test.dart)
(cd packages/muyon_module_api && flutter analyze && flutter test)
(cd apps/muyon && flutter test)
```

变异至少三项：改为double做询价金额→精确/微量舍入测试失败；沿用旧inputVersion发布参数变更结果→stale版本测试失败；跳过未知公式/输入引用检查→对应拒绝测试失败。不得弱化既有validator、改旧期望值或绕过业务校验来过测试。

回报：分支完整SHA、登记版本/名称与生产输入来源、已完成/依赖待实现逐项表、各公式单位/舍入与错误码、重算/恢复证明、analyze及测试通过/失败/未运行数、变异指定测试结果。原始日志不入库；摘要和可复算命令即可。本任务书草案本身没有执行上述测试，不是实现完成或接口正式采纳的证明。

## 分片执行检查表

- [ ] 在ui_formula_registry_test中逐项实现首批金额/税/缺值/单位负例并运行，保存有效RED摘要。
- [ ] 实现上述UiFormulaInvocation/UiFormulaEvaluation和纯evaluate接口及业务薄适配，supplier共有helper作为独立依赖补丁交owner。
- [ ] 运行首批专项及现有pricing/unit/store/research对照，逐项核对输出、舍入、输入未被修改。
- [ ] 提交纯公式片；科研投影/集合与runtime依赖另列，交AIUI-5端口联调，不把缺依赖测试skip计作完成。
- [ ] 按本任务命令与共同门禁复跑，交完整SHA/变异/未运行证据，唯一集成审查。
