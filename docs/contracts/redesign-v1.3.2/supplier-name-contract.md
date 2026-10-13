# M02 供应商名称领域合同草案

状态：`draft / blocked_contract`（部分语义可独立审查，未冻结 M03）。日期：2026-10-14 北京时间。真实 writer：Leader B 委派的 `redesign_m02_contract` agent；独立分支 `leader-b/redesign-m02-supplier-name-20261014`。

## 1 范围、固定来源与证据界限

首片仅合成供应商 detail/read、单字段 name update；确定性完整名称直接调用 Rust，零模型回合。本文提取现行 Dart 行为并提出迁移语义，不实现产品、不定义第二套 DTO/schema，不扩大联系人、停用、删除、价格、Hub 或外发范围。

产品事实一律固定在 **`01e56cc2d729dab70e1b1def05c3aa93b28f421a`**（下称 P）；设计目标固定在 **`58fe9c62612d74a973614c41677e62a54332e6d6`**（下称 D）。工作基线 `421e7332807d0f8a2f7a6a36819601dcad442130`。核查所引产品目录相对 P 的 `git diff --stat` 为空；以下行号属于 P，不取在途实现。依据文件和行号是可 review 静态证据，不是测试通过或 Rust/Android 已实现证据。

| 证据 | P 下精确路径及行号 | 已读取内容 |
| --- | --- | --- |
| E01 | `packages/supplier_core/lib/src/ontology.dart:133–139` | name 必需 text；description 的“最长200字”只作说明，执行证据见 E02 |
| E02 | `packages/supplier_core/lib/src/values.dart:3–10,33–69` | 错误、精确键、UUID、Unicode/trim/NFC/码点长度 |
| E03 | `packages/supplier_core/lib/src/entities.dart:11–46`；`packages/supplier_core/lib/src/quotation.dart:10–41` | Supplier 完整载荷和 validatePayload 路由 |
| E04 | `packages/supplier_core/lib/src/store.dart:361–372,378–398,435–439,481–514` | 按 type/id 读取、完整校验、版本增加、字段变更日志 |
| E05 | `apps/muyon/lib/platform/inquiry_record_tools.dart:44–59,80–179` | 工具 schema 和实际 preflight；原始字符串长度与类型 |
| E06 | 同 E05 文件 `185–244,273–303,336–374,390–465,518–570` | ObjectRef、scope、CAS、业务回执、事务写入及错误转换 |
| E07 | `apps/muyon/lib/platform/inquiry_write_receipts.dart:7–65` | canonical JSON、operation_id、scope 身份和摘要 |
| E08 | `apps/muyon/lib/platform/inquiry_receipt_lookup.dart:8–59,64–100` | 只读查业务回执；库文件路径身份、notFound/unreadable 区别 |
| E09 | `apps/muyon/lib/platform/tool_registry.dart:967–1048,1126–1142` | invocation 重复、身份冲突、单次宿主授权消费、结果不明与先查回执 |
| E10 | `apps/muyon/lib/app/adapters/inquiry_module.dart:209–266,273–300,328–338` | resolve 的当前版本/摘要、页面 tombstone 排除、name 类别 none |
| E11 | `apps/muyon/lib/platform/business_tools.dart:59–92,108–157,161–200`；`packages/supplier_core/lib/src/agent_tools.dart:315–342,567–576` | read/get/object 的范围、返回值差异 |
| E12 | `packages/inquiry_module/lib/src/features/catalog/detail_panel.dart:33–65`；`packages/inquiry_module/lib/src/features/catalog/catalog_form.dart:251–268,295–303` | 旧页面按 ID 读；表单重取 existing、trim、完整 save，无 expected_version |
| E14 | `packages/inquiry_module/lib/src/app/app_state.dart:715–725` | write关闭保护、FormatException转friendlyError |
| E13 | `apps/muyon/lib/platform/grants/host_authorization_policy.dart:9–33,43–105`；`apps/muyon/lib/platform/grants/host_tool_authorization.dart:249–263` | 旧三档准入不是 grant；缺失/损坏配置；review 故障 confirm 的局部行为 |

在线核查入口：[P 源码树](https://github.com/mightyoung/Muyon/tree/01e56cc2d729dab70e1b1def05c3aa93b28f421a)、[D 第一册](https://github.com/mightyoung/Muyon/blob/58fe9c62612d74a973614c41677e62a54332e6d6/docs/design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md) L712、L878–945、L949、L1119–1198；[D 第二册](https://github.com/mightyoung/Muyon/blob/58fe9c62612d74a973614c41677e62a54332e6d6/docs/design/redesign-v1.3.2-20261014/Muyon-Page-Design-Handbook-v1.3.2-2026-10-14.md) L789–801。本次实际核查本地固定源码，无网络动作。

## 2 现行名称规范：分清工具、领域与旧页面

E02/E03 的执行顺序：要求 String；逐 rune 检查 XML 合法字符；Dart `String.trim()`；`unorm_dart.nfc()`；非空；NFC 结果 `runes.length <= 200`。允许 TAB U+0009、LF U+000A、CR U+000D、U+0020–D7FF、U+E000–FFFD、U+10000–10FFFF；拒绝其他控制字符、U+FFFE/FFFF、孤立 surrogate。检查在 trim **之前**，不能用裁掉非法边缘字符绕过。内部 TAB/换行与合法空格不折叠；无 NFKC、大小写折叠、标点替换或“公司”后缀处理。Rust 的 trim/NFC/Unicode 版本及 XML 字符域须跨端差分证明等价，不能仅选择 Rust 默认 `trim()` 就宣称一致。

| 输入情况 | 现行领域行为 | 现行 update_record 入口的区别 |
| --- | --- | --- |
| `"  合成供应商  "` | 保存 `"合成供应商"` | E05 先检原始 String UTF-16 `length <= 2000` |
| `"e\u0301"` | NFC 得 `"é"`，1码点 | 不按 UTF-8 bytes 或 grapheme 数限200 |
| `"😀"` ×200 / ×201 | 前者200码点合法，后者 exceeds 200 codepoints | UTF-16分别400/402，均先过2000入口限值 |
| `""`、仅可 trim 空白 | `name: required` | schema 没有 name minLength；最终领域拒绝 |
| `null` | `name: expected text` | 字段 schema 明确允许 null；preflight 跳过 null，完整领域拒绝，不能清空必需名称 |
| `false`、`[]`、数值、对象 | `name: expected text` | 工具 schema/ontology 类型校验可先拒绝；preflight reason 为 Value does not match the ontology field |
| 缺省 name | 完整 Supplier 载荷缺键：`payload: missing or unknown keys`（E03） | 非空 patch 若只有其他合法字段，合并旧载荷保留旧 name；`values:{}` 被 E05 拒绝。缺 values 是 schema 缺必需参数，不等同 null name |
| 原始 `" "` ×2001 + `"甲"` | 直接领域可 trim 成合法 `甲` | 工具原始 UTF-16超过2000，先拒绝 approved size limit；旧页面预先 trim，和工具不完全等价 |
| `"\u0000甲"` 或孤立 surrogate | invalid XML character or isolated surrogate | 不因 trim/NFC 消失而许可 |

旧表单空白先转 null，因此旧页面空白名称错误可为 expected text；直接领域空字符串为 required。必须记录入口与错误层，不能用一条错误文案冒充所有路径。旧表单可改多字段、提交时重新读取 existing，Store.save 自身没有 CAS 参数；工具路径才有显式 expected_version 和选中快照检查（E12/E04/E06）。本文不会称旧页面已有首片 plan/CAS。

## 3 detail/read 与单字段写的现状

旧 detail 页面按 type/id 读取 Store.get；缺失或 deleted 显示已删除，不写入。Store.get 返回 version、deleted 和解码 data。`inquiry.get` 的领域结果缺记录返回 null，存在记录返回 id 和非 null 字段，deleted 仅为 true 时附出，**不含 version**（E11）。宿主 get read descriptor 使用 global scope，但 handler 的 requireScoped 仍检查解析 scope 内身份。`inquiry.object` 返回 `record.data`（保留 null）及选中 ObjectRef，不单独把 version 放进 data。两者均不是自动获得全部 supplier 读取权；首片 read projection 不应直接搬整 record 的所有字段。

ObjectRef 的身份为 moduleId=inquiry、objectType=supplier、objectId、nativeProjectId；revisionRef 是 row.version 的十进制字符串，contentDigest 是数据库原始 JSON UTF-8 的 SHA-256（E06/E10）。supplier 通常全局 nativeProjectId=null；必须检查实际数据与绑定，不能把“全局”解释为任意 scope。resolve 缺记录、错 module/type/nativeProject、已固定 revision/digest 不符时返回 null；未 pinned tombstone 不解析，页面始终排除 deleted（E10）。名称不是身份，同名供应商不得串行。

旧单字段工具调用是已有 `inquiry.update_record`，参数语义：operation_id（小写 UUIDv4）、type=supplier、id（小写 UUIDv4）、expected_version（schema integer>=1）、values 只含 name。这只是现有参数形态说明，**不是新增产品 schema**。现行 generic 工具可更新其他合法字段；首片必须额外限制确切 name 一字段，保护字段及未知字段拒绝。

E06 在同一 Store.transaction 中依序验证参数→检查整个 selected scope 的当前 identity/revision/digest/workspace binding→目标必须被选中→查询 `reg4c:operation_id`→校验存活状态与 expected_version→完整旧载荷合并 values→领域验证/数据 scope→`checkBeforeEffect()`→Store.save→结果与回执入 meta。异常跨最外层事务后才转换 WriteConflict，保证 rollback。Store.save 再做完整领域校验，version +1；即使规范后 name 等于旧值仍 +1，但字段日志只记录真正不同字段（E04）。其他已存在字段保留且重新校验；名称相同不创建新对象，也没有名称唯一约束证据。

当前错误层应保留事实：preflight FormatException→`invalid_parameters`；选中不符→scope_changed；目标不存在/删除、expected_version不符→version_conflict；同 operation_id 异参数或范围→operation_id_reuse，均以 ToolCallStatus.failed 携可信 fieldPaths/currentVersion。AppState.write 的 FormatException 经 friendlyError 返回 error summary（E14）。调用未进入效果或有权威回执才可给确定结论；不可将所有 failed 文案转换成“绝无效果”。

两层幂等不能混淆：E09 的 invocation/replay 身份匹配可返回已有 result；相同 ID 身份不同为 idempotency_conflict；已有记录无 result 为 interrupted。E07 的业务回执 arguments 绑定原 operation、全参数与 canonical scope（workspace+排序对象身份，不含 revision/digest；expected_version 仍在参数里）；receiptKey 只取 operation_id。E06 先 `_currentSelection` 再查业务 receipt，因此成功后旧 selected revision 重发 handler 可能先 scope_changed；专用 E08 查回执无需重跑写。E08 还要求对应库身份（现行为数据库文件路径摘要）；内存库不可读，路径移动会身份冲突。该身份方案不自动成为新版 store_id。

## 4 旧事实与目标差异

| 维度 | P 事实 | D 目标 / M02 建议 | 待闭合 |
| --- | --- | --- | --- |
| 名称 | XML字符→trim→NFC→200码点；工具另限 raw UTF-16 2000 | 继承规范；保持工具额外限值为入口兼容差异，别静默取消/扩大 | M03 同源规范与 Unicode 差分；入口限值统一选择需记录 |
| 详情 | 页面/工具可取完整 record；get 无 version | 目的限定的 supplierId/name/revision 投影；显示保存值与草稿 | M03 统一表示、D03a projection |
| 修改 | 旧页面多字段无 CAS；generic 工具完整 merge+CAS | 仅 name；Rust plan 返回规范参数、预期 revision、读写集与校验；保存送 plan_ref | 不造另一套 Dart/Rust DTO；M03 唯一权威源 |
| 身份 | ObjectRef、UUIDv4、version/string digest | 稳定 supplierId 与 ObjectRef 语义继承；名称不参与身份 | store/scope/stream 身份归 M03/D03a |
| 幂等 | invocation 与 operation 两层；先 scope 后业务回执 | 同意图预览/保存双击、IPC重发和重启复用原 key/结果；同ID异payload冲突 | D03a 恢复及 M03 状态/摘要域 |
| 同值新意图 | Store.save 同值仍 bump version | 本草案建议继承 +1；与同意图 replay 不重复写区分 | 非作者审查确认该产品语义后 M03编码 |
| 成功 | committed result 和业务回执，同事务 | “已保存”只由真实 EffectReceipt 驱动；dispatching 非成功 | D03a 迟到回执与 unknown核对 |
| 模式 | standard/readOnly/custom；settings 不供 grant，review 局部故障confirm | 正式只读/每次询问/Auto/全部允许；新装Auto；不是旧enum换名 | D01a最小模式，D01b旧映射与期限 |
| 分类 | 已声明 supplier.name=none；未证明统一输出检查存在 | 字段类别 ∧ 模型实际新值宿主输出/credential检查 ∧ 当前用途授权 | A00规则未注册；D01b真实出口 |

## 5 Rust 确定性动作与恢复语义草案

可信页面输入完整名称→建立稳定 intent_ref/本机草稿→Rust 预览在当前对象/授权事实下检查单字段、规范值、读写集/不变量和 CAS→返回 plan_ref、规范参数摘要、预期 revision 与结果→保存直接提交同 plan_ref。输入变化或事实变化使旧 plan 失效；不能检查一个值而执行另一个值。UI 只编辑草稿，不直接写库；调用预算为 **0 model requests / 0 external sends**，包括分类也不为满足规则多开模型轮次。

重复点击、响应丢失重投递和重启恢复属于同意图，保持 intent/plan/action/key、参数摘要和原结果查询，不铸新 grant、不换 expected_revision 伪装重试。同ID异payload/scope 显式冲突，不允许就地改 key 吃掉冲突。合法再次意图是原结果已核清后用户明确再次编辑（例如 A→B 后再次 B→C，或明确再次提交 B）：新 intent、新预览/计划和当前 revision，执行点重新授权。旧 unknown 不能通过“再次意图”按钮暗中补发；须先核对或明确隔离，显示可能已有的效果。

超时、进程退出、dispatching 无确定回执→unknown，先查询原权威业务/执行回执；notFound、损坏或不可读均不能单独证明未执行，仍 unknown 并给可用核对路径。cancel_requested 不等于 cancelled；取消不撤销已提交改名。真实迟到 EffectReceipt 即使来自旧展示 epoch 仍进账并更新事实；旧 UI callback 不可覆盖新草稿。断网且本地库/能力确可用可读写；能力缺失保留草稿与明确依赖，不能模拟离线成功。读取权撤销清允许范围外的详情/搜索/草稿投影，撤写权禁新派发；已派发效果继续核对。CAS 同字段冲突保留原输入并展示当前版，禁止只换 revision 覆盖；仅经完整读写集及关联不变量证明无冲突才允许自动重建。

以上身份、状态与字段是 D 既有术语及 golden 所需语义，不在本文定义 wire spelling、Rust struct、JSON schema 或另一套状态 enum；最终定义唯一归 M03。

## 6 四正式模式与 legacy 边界

| 模式 | 首片 read | name update / 确定性链 | 未定项处理 |
| --- | --- | --- | --- |
| 只读 | 当前允许投影 | 可草稿/预览，不提交；model 独立设置不推导联网许可 | 不由 name=none 自动 grant |
| 每次询问 | 当前允许投影 | 对当前意图确认后执行；scope/CAS/真实能力仍需通过 | 旧 grant复用映射未定记 blocked_contract |
| Auto（新装默认） | 当前允许投影 | 版本化 Rust RiskDecision 低风险自动、高风险确认 | 最小规则/期限未冻结的具体 case 为 blocked_contract，不造通过，也不设永久 confirm 默认 |
| 全部允许 FullAllow B | 当前允许投影 | 有效scope/用途/能力/业务合法内，包括高风险/taint，零额外风险确认 | 不因纯风险评分/审查故障变隐形暂停；模式能力表示和fixture期限仍待D01a |

FullAllow 新网站/API 零首次询问是已定目标，首片无真实外发只可假传输断言；本合同不重开该决定，也不冒称 Dart 已实现。始终拒绝真实无权/撤权、可信禁用途、非法业务、不可绕过系统限制；credential不能进模型/业务正文，unreviewed不外发。风险建议与硬限制必须分别记录。name=none 只说明基础类别，非grant、非scope证明、非执行成功。

旧 absent config→legacy_standard，损坏/写入锁存→fail-closed；standard 保留旧四维准入+grant/事实，不等同 Auto 或每次询问。readOnly 保留禁 write/outbound 且 model 独立；custom 保留四维、revision、原规则。旧 once/task/conversation/timed/always 的范围、目的地、到期、消费次数、撤销与外传会话上界不能延长；旧 outbound 不得迁成 always。正式新档只能由真实主动选择产生新版模式能力，不能将新装Auto套迁移库。切 FullAllow 不恢复旧 grant、不重发 unknown、不解除 capability_hold。D01a最小模式语义和假服务验证先行；完整旧映射/ModeGrant期限属于 D01b，本文不代冻结。

## 7 分类组合与可执行 fixture 语义

复用 [A00 分类目录](../../tasks/redesign-kickoff-20261014/Muyon-A00-Classification-Fixture-Catalog.md) §3–§5：14拟定规则全部待冻结、29子case 全部 `not_run`；本文没有执行或注册它们，没有增加主验收编号。模型生成 name 必须同时满足 CLS-DECL-001、CLS-MODEL-FIELD-001、CLS-CREDENTIAL-001，保留真实来源/版本/继承限制，再经 CLS-PURPOSE-001 与模式门禁；干净且覆盖完整者可继承 name=none。命中→credential；疑似/缺输出规则/失败/覆盖不足→unreviewed，no_coverage 终止本次尝试并说明原因，不无限spinner。采纳模型输出不改标用户原创；纯确定性用户编辑无新模型输出则不要求不存在的模型输出规则。分类通过与动作允许分别判断；Auto合同未定只阻动作金标，不阻独立分类验证。

下表是 M04 可执行离线合成输入/期望，不是新 schema 或已跑 tests。基本对象：两个不同合法 supplier UUIDv4 S1/S2，同名“合成甲”，version=1、全局 scope、完整合法其他字段（aliases/categories为空数组，其余可选 null），真实合成内存/文件库身份由执行器声明。所有持久/回执核对用隔离合成文件库；不得拿内存库伪造旧 E08 成功。字符串用生成器表达式构造，不粘贴真实秘密。

| case | 输入/步骤 | golden 语义 |
| --- | --- | --- |
| N01 | name=`"  合成乙  "`，S1 rev1，仅name | 保存“合成乙”，S1 rev2，S2 rev1；其他字段语义不变，真实回执一次，model/send计数0 |
| N02 | name=`"e\u0301"`；另 name=U+1F600×200 | NFC“é”/200码点合法；跨端规范参数及摘要一致 |
| N03 | U+1F600×201；空字符串；TAB/LF/CR仅边缘空白 | 超长/required；无业务写、无成功回执；草稿保留 |
| N04 | null、false、[]、数字、对象；缺name；name之外字段/空patch | 首片命令精确单name拒绝；旧入口语义单独对照§2，不能把旧缺name patch误写成清空 |
| N05 | NUL/孤立surrogate/U+FFFE；内部LF；U+FFFD | 前三拒绝；后两合法且内部LF不折叠；规范前检查，诊断不回显敏感值 |
| N06 | raw空格×2001+甲 | 旧工具raw限值拒绝，直接领域甲合法；目标入口限值未定部分 blocked_contract |
| I01 | 同名S1/S2，只选S1改名 | 只改S1；未选S2拒绝；缺失/deleted身份无更新 |
| C01 | 双窗口读rev1，各改不同name；第一保存后第二旧plan | 第二CAS拒绝、无第二写；保留第二草稿并显示当前保存值，不悄悄换revision |
| C02 | selected digest/revision/workspace变；撤写权在派发前 | 拒绝执行；读投影按当前读权；参数变化旧plan失效 |
| R01 | 同意图双击/IPC重发/重启恢复，原key原payload | 最多一次业务效果、同回执；不得新增意图/授权。旧handler先scope检查差异另留证据 |
| R02 | 原key改name或scope | 幂等冲突；无第二写，无自动换key |
| R03 | 成功后用户明确新意图改同值或再改C | 新plan/current revision/新key；同值按本草案+1建议核查；不是 replay |
| R04 | 提交后丢响应，回执可查/不可读/notFound | 可查且身份验证才报已保存；否则unknown；零自动重发、零凭超时判失败 |
| R05 | cancel与commit竞态、旧epoch迟到真回执 | cancel_requested不伪称cancelled；已提交保留；真回执进账、旧展示不覆盖新输入 |
| A01 | 四档，同合法事实，合成低/高风险版本化样本 | 只读不写；每次询问当前意图；Auto由D01a规则金标；FullAllow高风险零风险追问；未定Auto/期限 blocked_contract |
| A02 | legacy缺失/损坏/standard/custom/readOnly/旧grant到期或撤销 | 缺失旧兼容，损坏闭合，显式旧开关和期限不升权；不标legacy_standard=Auto |
| F01 | 假模型输出干净完整name，字段声明+输出规则+credential complete | 分类none且真实来源保留；FullAllow当前用途可派假载荷，Auto动作视已冻结规则或blocked_contract |
| F02 | 假输出合成canary命中/疑似/规则缺失/覆盖失败 | credential禁正文或unreviewed不外发；普通confirm/FullAllow不解除；缺覆盖终止，最终假传输捕获无禁内容 |
| F03 | 先检查v1，提交时参数或输出v2；未知字段枚举 | 旧分类证据失效，重验或阻断；未知unreviewed；不能套旧默认none |
| F04 | 完整用户确定性name且无新输出 | 直Rust，0模型轮；字段/来源/实际值/用途按相应覆盖检验，不为分类造模型回合 |

每个 golden 记录最少语义：case/version、P/D及执行构建SHA、source/来源引用、输入内容版本、字段声明/Unicode/规则版本与覆盖结果、原规范参数与摘要（只合成可保留文本）、supplier身份及旧/新revision、scope/读写集、intent/plan/action/key关联、当前mode/policy/authority revision、期限/撤销事实、风险规则ID/结果或blocked_contract、状态前后、回执权威/查证结果、对象变化与写入次数、模型/传输计数及合成最终payload捕获、安全原因码、执行结果/证据路径/非作者复核。金标不要求把被挡凭据原文复制进日志/差分/历史；仅合成canary与允许最小元数据。wire字段名和摘要域由M03统一，不据本清单另建DTO。

## 8 冻结门禁与未知

M02草案→D01a 最小模式/假输出与假传输组合、D03a 最小恢复/投影合同、SPIKE-01 同语义双传输与真实 Android 库加载证据协调→M03 唯一schema/编码冻结。没有真实 Android 库加载证据不得冻结 M03；本 writer 未取得该证据。业务 Unicode/入口兼容差分、同值新意图建议、RiskDecision 细则、ModeGrant期限、旧模式映射、恢复身份及cursor/快照/迟到回执表示仍有待定项，逐case写 blocked_contract。

52主验收及A00 29分类子case没有因本文变为已执行；现有 CI 不替代新架构验收。本文交付可审查领域事实和目标草案，产品writer尚未在本任务分派；不占有23单元实现，不冻结ADR，不推送/合入。Leader B responsibilityB custodian 是唯一develop集成人。
