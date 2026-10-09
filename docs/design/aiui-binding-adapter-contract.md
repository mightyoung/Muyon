# AIUI-5 F5a binding adapter proposal — DRAFT

状态：**draft / 未采纳**。仅供唯一集成负责人及契约所有者决策；本片不修改正式 schema、stream/1、runtime、export、目录或存储。F5b/F5c 依采纳记录另做。基线 `0466f113fd7dd41f99c38cef11eca428622a6fac`；任务书 `82df0f29d9628d107d96d52795438e972ce5fefe` 的两份文件与基线逐字相同。远端开工无其它 AIUI-5 分支；保留 AIUI-1 `276b29146d3eb902380cceac708209cc6ef344c0`、AIUI-2 `4e45836efcb85c86f5c8de57e6b07795aab6166a` 已合入身份。基线CI 37971444082及首片 b2886075afb1c56289506d5ffc8e834116ba5254 的CI 37974253299均已通过只读GitHub连接核实success；本地gh API403与缺SDK是独立环境限制。

已读项目总览现行决定、HANDOVER-LEADER、ADR-0001、AI 原生界面方案、REVIEW、正式 stream 契约、AIUI-2 interface-followup 及现有生产消费入口。仓库及 `/workspace` 无 AGENTS.md 或仓库 skills；不重复 F3a 公式实现、AIUI-4 外壳或其两个旧恢复测试。本地没有 Flutter/Dart，不下载 SDK 绕过已知受限端点。

## 1. 决策包与取舍

建议采纳以下四项为**一个完整增补**，不能只放宽 scalar/edit gate：

| 议题 | 建议（draft） | 取舍/另一方案 |
|---|---|---|
| typed edit | 宿主声明 `UiEditSpec`，string/bool/finiteNumber/date/itemIds；事件与目标 spec 精确匹配 | 仅 string 不支持现有 Toggle/Slider；全局 num 或动态类型会丢失范围/身份约束 |
| collection | 在 DataSnapshot 增加专用 host collections registry；新增 draft `collection` kind，BindingRef仍仅kind/id，slot schema声明集合形状 | 不接受 JSON 字符串包装过 scalar，也不允许任意 List/Map 成为 fact。字符串对照只能说明旧 gate 行为，不能标集成通过 |
| row detail | payload 用宿主 stable row ID + collection revision；由当前 host registry 解析可信 ObjectRef | 标题、行位置、模型提交 ObjectRef 都不可作身份；暂保只读，不擅自删除 library-1 tap |
| 版本 | 候选 `library-2` + UI snapshot/edit/collection/workspace capability revision，具体字符串待采纳 | 不改library-1同名字段语义；旧minimal-1/dynamic-1继续读。因建议新增collection kind，必须单独采纳stream/2；stream/1不兼容此新kind，不能只以行外形未变宣称v1兼容 |

采纳记录：**未决定**。下游只可引用本文件作讨论，不能按 draft version 开启生产能力。需要 owner 明确批准上述组合、number 精度政策、choice 自填登记政策和恢复版本；当前 disabled/可信文字模板仍有效。

## 2. typed edit（draft 精确语义）

宿主声明 state key、type、nullable、范围、step、collection membership、scope；模型仅引用该 key。现有 string 编辑保持原样。typed 编辑的 gate 同时核对目录事件、host spec、绑定、intent、当前 plan revision 和 state；wrong type/未知 state 拒绝后值及 draftRevision 不变。编辑仅更新允许 UI 参数和人工 override，不能写 fact 或业务 draft；sort/纯浏览selection/展开属于view，不递增draftRevision；Choice的参数选择另按宿主声明分类，不能统称view。

- bool 仅 true/false，不接受 0/1 或字符串。
- finiteNumber wire 为 JSON number；整数模式要求数学整数且在安全整数范围 ±(2^53−1)。小数模式保留 double，不 `toInt`；金额继续使用领域定点 evaluator。min/max/step 由宿主 finite 数声明，min≤max、step>0；闭区间；离散 step 检查 `(value-min)/step` 距最近整数 ≤1e−9，拒绝 off-grid，不静默 clamp/round。Slider divisions 仅当区间/step 可整除且 divisions 为 1..10000 整数；否则 continuous，仍保范围，step 有约束时不能用 continuous 绕开。min=max 显示只读常量。
- date 是严格 `YYYY-MM-DD` Gregorian 日历日期（0001..9999），验证真实月日与闰年；无时间/时区，禁止 timestamp 和自动 UTC 转日。DateTime Widget 仅用 year/month/day adapter 构造及读回；first/last 由同一 host spec 给定，不靠 DateTime.now 默认范围。nullable 显式声明才可 null；空字符串不是 null，拒绝 2026-02-30、2026-1-2、时区后缀。
- itemIds wire/persistence 为 UTF-8 字典序稳定排序的去重 ID 数组，绝不存 Set；重复输入直接拒绝，不能先去重后通过。single 最多1个、multiple ≤集合项上限；每 ID 必须属于当前 host collection/scope/revision。Widget Set 只作已验证视图投影。自填 Choice 初版 disabled：标签不是 ID；后续若采纳由 host 本地登记稳定 draft ID 后再选择，不能模型/Widget自行发明 ID。
- Choice宿主声明用途 `parameterEdit` 或 `viewSelection`，模型不能改变角色。parameterEdit修改已声明参数uiState/userOverrides，值实际变化或首次明确覆盖时递增draftRevision；若该key是登记公式依赖，冻结新输入并走§5重算，旧pending operation/confirm需重新核对。未依赖该参数的公式无需重算，但确认仍按草稿版本失效规则处理。viewSelection只改viewValues（例如浏览候选详情或视图过滤），不递增draftRevision、不触发参数公式重算、不改变business draft；宿主不能将viewSelection key同时登记为公式参数或business输入，角色冲突整项拒绝。两种选择均核对当前membership/scope/revision；恢复保留角色与override/view分层，不因相同ID数组形状互换语义。
- Checklist fact 模式只读；宿主声明 checked state 投影，点击回传 stable item ID + bool。当前 index,bool callback 只可由已冻结渲染映射转 ID；排序后位置不能成为持久身份。

## 3. collection codec 与身份（draft）

### 3.1 binding解析与协议门槛（draft修订）

明确选择独立 `BindingKind.collection`（拟新增，尚未实现），不让fact/computed/uiState隐式查另一个registry：

| kind | 唯一解析目标 | 状态 |
|---|---|---|
| fact | snapshot.facts[id]；现行scalar/identity/source校验 | stream/1原规则保持 |
| computed | snapshot.computations[id]；现行scalar、computationId/inputVersion校验 | stream/1原规则保持 |
| uiState | snapshot.initialUiState[id]；宿主状态声明 | stream/1现行scalar保持；新版typed状态须另采纳 |
| collection | snapshot.collections[id]；专用codec/slot shape、来源及版本校验 | 仅拟议stream/2 + 新catalog能力版本；v1拒绝 |

因此`fact/computed/uiState`三个kind**都不解析collections registry**。集合entry内部的producerKind=fact或computed只声明宿主数据来源，不是BindingRef.kind；computed collection必须核对稳定computationId、inputVersion及dependency fingerprint；itemIds选择是独立typed uiState，不能把整集合塞进uiState。新目录的rows/data/options/items/events集合slot显式允许collection并声明期望shape，旧目录不变。sourceSpan不走集合。

宿主在冻结snapshot时检查collectionId不能与facts/computations/initialUiState任一已声明id同名；发现重名整份collection注册/新snapshot批次拒绝`collection_scalar_id_conflict`，不设置查询优先级、不把scalar改成集合、不吞掉其中一个。旧scalar各kind之间的现有命名行为不在本片改变。collections只由host登记；缺失id、错producerKind/slot shape、旧版本、错scope或unknown codec均整集合拒绝，不能fallback到scalar Map查找或解码字符串。

具体draft金样：`docs/fixtures/aiui5/collection-binding.draft.json` 的rows绑定是`{"kind":"collection","id":"quote-comparison"}`，宿主registry登记两个稳定row及cell状态引用。`negativeCases`给出同名scalar/不存在collection/用computed或fact冒充collection的最小差异与预期拒绝。模型只发送kind/id；host envelope、cell状态、版本和可信ObjectRef均不在模型行里。该文件标future-only，仅产物一致性检查；现行stream/1 parser拒绝collection kind的真实负例由新增Dart测试消费同一模型行。新kind明确违反v1枚举，故必须另提stream/2，**当前生产仍按stream/1拒绝**；不修改正式schema/runtime。

### 3.2 codec、cell旁路状态与身份（draft）

专用 registry entry 的确定 JSON envelope：`codecVersion, collectionId, collectionRevision, snapshotRef, scopeKey, sourceVersions, columns, rows, cellStateRefs, cellStates`。columns 为有序 `{id,label,type,nullable,unit?}`；rows 为有序 `{itemId,cells,rowObjectRef?}`；cells 按 column id 存 typed primitive，不允许任意嵌套数据。对象引用仅宿主提供 `{moduleId,objectType,objectId}`，宿主 registry 另保存对象/source revision，不能把模型自报 ref 入 registry。sourceVersions 必须解析到当前宿主 digest/version；计算集合附 computationId/formula definition version/inputVersion/fingerprint，Chart 值来自事实或 host computation，不来自模型 props。

每个cell以稳定`(itemId,columnId)`通过`cellStateRefs[itemId][columnId] -> stateId`关联宿主`cellStates[stateId]`，状态entry含`state:FactState`、`missingReason?`、`valueRef:{kind:fact|computed,id}`、`sourceRefs`。stateId仅host声明的旁路引用，不是模型binding或第三份值：valueRef必须解析到同一snapshot的真实scalar fact/computation，cells中的值必须与该引用值等价（严格类型、finite数），fact引用的state/sourceRefs也必须一致；computed引用需同inputVersion且状态/source由host依赖评估提供。缺失/重复/孤立stateId、未知valueRef、错state/source/digest/值、模型自报状态及未覆盖cell全部拒绝。计算集合的宿主状态不能因producerKind=computed就默认verified。

`null`必须由nullable列允许且有宿主missingReason；闭合原因枚举拟为`not_disclosed / not_applicable / read_failed / source_missing / explicit_null`。notDisclosed/notApplicable/readFailed分别只能配对应原因及null；unverified null配source_missing；verified null仅表示宿主明确空值explicit_null（nullable），不冒充未知。verified/unverified/conflict非null值保其FactState且不设缺值原因；需要表达超出此表的组合须先补契约，不能猜默认。空字符串是宿主真实字符串值，不是unknown占位，不能用它替换null；数字null不得转0。Widget按state和原因显示只读“未披露/读取失败”等文字等价物，复制/读屏也包含状态，展示标签不写回cells。collection绑定的必显状态检查覆盖所有cellStates，对mandatory state不能只算整表已显示而隐藏问题cell。

金样有quote-a price=10/verified与quote-b price=null/notDisclosed/not_disclosed，两者各自引用宿主facts及source版本。负例把quote-b的null改成空字符串或删除missingReason/cellStateRefs时分别拒绝值不一致/缺值原因缺失/状态引用缺失，不能删坏cell后通过。恢复按稳定row/column/stateId重核来源和状态；未知schema或状态映射整组只读、保原bytes/人工稿。

集合 ID/列 ID/项 ID 不为空，在 collection+scope 内唯一；稳定 item ID 随重排保持、删除不可复用为另一对象。同显示标签可重复，同 ID 不可重复。不可编辑 cells 是事实投影；可编辑 checked/selected/参数放独立 host typed state，绑定 membership revision，不能修改 registry facts。Table/KeyValue/CompareTable/Timeline/Chart/Choice/Checklist 按各 slot 期望 shape 转换；Chart 类型仅 bar/line/pie，pie 负值拒绝，不默默改0；CompareMark 由宿主判定，不能来自模型 highlight 字符串。

共享常量建议：200 rows/items、32 columns、depth4、单字符串4096 UTF-8 bytes、单集合65536 encoded UTF-8 bytes；state itemIds 同200上限。总 workspace encoded byte 限额建议256KiB；单 surface 仍同时满足既有200 nodes/depth12/stream limits，更严格者生效。边界包含N；测试必须使用同常量造N−1/N/N+1，字节按UTF-8（含转义后的编码）计算。编码对象 key 排序，列表 order 保留（选择 ID 数组按字典序），JSON number finite，不允许 NaN/Infinity；字节往返应确定。

整集合拒绝：未知 codec/version/字段/type，空/重复 ID，缺必填 cell，未知 column，错型/非有限/无效日期，未知或撤销 source/ObjectRef，错 scope/snapshot/collection revision，超数量/深度/字节，畸形 JSON。不得丢弃坏项或填合法默认值后通过。null 只在对应列 nullable 时允许，并保事实 state/missing 原因，不把缺值当0。

## 4. CompareTable 详情（draft）

事件形状：host adapter 生成 `{collectionId, collectionRevision, itemId}`，不含 ObjectRef、标题、index 或 route。validator 确认 rows slot 的专用 collection schema 与允许 detail action；Widget 在当前 render projection 按 stable ID 发事件；唯一 controller 验证 observed surface revision 后解析当前 registry，对 rowObjectRef 和 current scope/object revision 再读校验；local host navigation 打开该 ObjectRef 的只读页。UiPlanningEventRouter 仍是业务/语义宿主边界，本地详情不能假装 business tool。没有 ObjectRef 的行无回调。未知/删除/过期/伪造/跨scope row 零导航、零工具。排序改变 view order，不改事实或业务 draft。

目前 openDetail 仅存 detailNode，CompareTable 无 value 导致 detail_input，纯 Widget 没 row callback；均保持正式阻断。不能把 rows alias 成 value，也不能用整表对象冒充行。AIUI-4 导航返回消费以后由已审接口接入。

## 5. 一个版本批次的宿主构造责任（draft）

复用唯一 UiSurfaceController/UiSessionState、validator、planning harness、gateway 与 store；不新增 runtime/validator/router。F3a 仅 pure evaluate。host adapter 冻结 baseSnapshotRef、来源版本、当前合法 UI state、observedDraftRevision、scope/permission generation；分配 S8 后以**S8实际输入**调用登记公式，记录 formulaId/version 与不同的 computationId、dependency fingerprint。构造不可变最终 S8，再构造 I8.snapshotRef=S8 与 P12.snapshotRef=S8、intentRef=I8.id、revision>旧P11；从当前权限重建 allowedActionRefs 不扩大授权。对(S8,I8,目录)整树 validate 后迁移相同 stable key/type/membership 的人工覆盖/view，再在同 controller 原子替换。发布前核对 baseSnapshotRef/draftRevision/权限generation，竞争变化则整批丢弃。

最小金样见独立 Dart `aiui5_f5a_contract_fixture_test.dart`：S7 price='10'/qty='2'/total='20'，S8 qty='3'/total='30'，ComputedValue.inputVersion=S8，I8/P12同S8。同一登记计算实例的computationId固定`host-total-instance`并跨S7/S8保持不变；它与formulaId（定义）、snapshot revision/inputVersion（输入版本）分别承担身份/定义/版本责任，不能从revision派生实例ID。数值明确宿主公开fixture，非模型输出。Dart夹具用纯fixture乘积示范构造责任，**不是 F3a evaluator 或真实编辑重算接线**。

只给缓存20重标S8不能证明新输入计算：inputVersion相等是必要条件，不是充分条件；现行 validator 没 fingerprint，可能接受20。提案要求 host evaluator比对 frozen依赖并重算，禁止用改版本替代计算；混搭I7/P11已有 snapshot_revision 拒绝。公式失败/晚到结果不得发布旧成功结果作当前值；保留人工draft与旧界面且明确过期/失败，撤销过期confirm能力。业务operation由host重核；重算不授予权限、恢复不重放写入或模型调用。

## 6. 全目录生产→消费与恢复

机器清单 `docs/fixtures/aiui5/component-mapping.json` 由 `python3 scripts/aiui5/check_artifacts.py --write` 从真实 catalog 的继承、覆盖及两个for展开生成。每项含完整schema（属性/必填/children/binding kinds/events/actions）、来源行号、现行 renderer case inventory、surface catalog gate 和 fallback、目标Widget参数、当前与拟议payload、validator/state/router/restore入口、文字/4态、现行fixture和未来验收名。33项=12已有+21新增；**12仅是源码render case统计，不是library-1可渲染能力**。surface.dart build仅接受identical minimal/dynamic catalog，library-1整棵表面进入snapshotFallback，render根本不调用。新增21项无render case；即使移除目录门禁也只会default unavailable文字。既有12项不自动获得library的4态。fallback仅显示intent要求的facts/sources，不负责计算集合或图表等价展示。

Tabs host声明稳定 child IDs及相应labels，要求一一对应、非空，view selectedChildId；当前目录只有children，无 labels/受控选中项，采纳后补schema+Widget adapter并保留已修shrink回归。Disclosure多children合成Column传单child，expanded为声明view state。Heading level只1..3，不靠Widget clamp消化非法整数。Form只读必须封住后代真实输入+submit，不只关提交按钮。文字等价与读屏用同一已解析可信值，图表附同source数据表；ready/loading/error/readOnlyDegraded不能启用未校验事件。

恢复仍沿 encode/decodeUiPresentation→StoredUiWorkspace→UiWorkspaceController→HostUiWorkspaceStore CAS。新typed/collection版本正式采纳后分别存明确codec envelope，保 stable IDs/source/input版本/override 与 view分层。未知版本/shape变化/删除node或绑定/type变化/权限失效：保原始bytes、可读旧draft与旧checkpoint，readOnly并给具体原因，不能清空覆盖或猜历史授权。超限保存拒绝新checkpoint，当前可读稿仍在；迁移纯投影、幂等，失败保原bytes；仅最终ValidatedUiPlan可保存操作能力，恢复对当前snapshot/intent/catalog重新validate且查询真实operation receipt，不重放business/semantic/model。

AIUI-4独占旧 `dynamic_workspace_return_test.dart`/`ui_workspace_store_test.dart`，本片不改；F5c将用独立 `ui_bound_workspace_recovery_test.dart`。旧字段变更以补丁交owner。AIUI-6/REG-4c未登记工具时 business submit/confirm不可用，不猜tool ID。

## 7. 验证分层与交接

实际可运行且不依赖新schema：Python仅核对清单重生成一致性、完整源码证据/引用、draft向量类别和JSONL结构（**不运行validator/Widget/codec**）；新增Dart测试调用正式validate/stream compiler/state/encode-decode/StoredUiWorkspace，assert现行合法string同版本投影与typed/collection拒绝。Flutter不存在则明确未运行，不用Python模拟宣称产品通过。

`draft-vectors.json` 仅未来正负用例数据，expectedAcceptance='future-only'，不声称新codec已存在；有限number/date/ID/详情/恢复拒绝需F5b/c在正式入口消费。N±1夹具由未来共享常量生成，不能另造Python版生产validator。流协议规定4变异、真实33组件Widget、CAS/SQLite/browser/实机/模型均属未来验收。

命令：`python3 scripts/aiui5/check_artifacts.py`；有SDK后 `cd packages/muyon_ui && flutter test test/aiui5_f5a_contract_fixture_test.dart test/library_contract_boundary_test.dart`，`cd packages/muyon_module_api && flutter test test/ui_stream_test.dart`；最终 `bash scripts/ci.sh`。本片摘要见独立任务回报，不冒充F5b/c完成。
