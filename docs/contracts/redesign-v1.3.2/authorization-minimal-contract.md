# D01a 首片最小授权模式合同草案

状态：proposal / 未冻结 / 全部 fixture draft、not_run。日期沿本任务标识 2026-10-14；不把文档检查记为产品验收。本文仅为首片提供可独立审查的语义合同，不定义第二套 DTO/schema，不冻结完整 D01b、ADR 或 M03。

## 1 固定来源与证据性质

| 来源 | 固定版本与定位 | source fact 或已定目标 |
| --- | --- | --- |
| 产品 P | `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；`apps/muyon/lib/platform/grants/host_authorization_policy.dart` L9–105 | 旧模式 standard/readOnly/custom；类别 read/model/write/outbound；设置只能收紧，不能自授 grant；缺失旧 standard、损坏 fail-closed |
| 工具 P | 同 SHA；`packages/muyon_module_api/lib/src/context.dart` L59；上述 policy L28–33 | ToolEffect read/write/export/network；read→read、write→write、export/network→outbound。model 是独立授权类别，不能拿 network 替换 |
| 设计 D | `58fe9c62612d74a973614c41677e62a54332e6d6`；[第一册](../../design/redesign-v1.3.2-20261014/Muyon-Redesign-Plan-v1.3.2-2026-10-14.md) 第6章、D01a/D01b L1186–1192 | 四正式档、新装 Auto、FullAllow B、新端点/taint/高风险免额外问、真实硬限制保留、首片假传输；为已采纳目标，不宣称 P 已实现 |
| 设计 D 页面 | 同 SHA；[第二册](../../design/redesign-v1.3.2-20261014/Muyon-Page-Design-Handbook-v1.3.2-2026-10-14.md) 总则、D01.1、T02/T03、S04 | 完整确定性业务参数直 Rust；模型和工具双出口；能力暂停与单次内容复核分开 |
| A00 | [已接目录](../../tasks/redesign-kickoff-20261014/Muyon-A00-Classification-Fixture-Catalog.md) §3–5；[盘点](../../tasks/redesign-kickoff-20261014/a00-inventory/Muyon-A00-Readonly-Inventory-2026-10-14.md) | 14 proposed 规则、29 not_run 子case；M01 intake 核对109不同 blob的登记是上游证据，本文未重跑全部盘点 |
| M02 | `/workspace/Muyon-leader-b-redesign-m02-20261014`；`642a939846a8f87e1fc8872142baa5ab755e1d02` 已获非作者 C0；本文读取领域决定修订 `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0` 的 supplier-name-contract.md | 三项领域决定见§4；642的C0不自动覆盖后续delta，M02仍不是M03冻结证据 |

D01a worktree 基于 `c3d937ad22a7f9061ad1c6591dbfbec8c36e6e2d`；只允许本文及任务登记两路径。四个核心 P/D 文件已逐字对比固定 git blob；没有访问真实库或运行模型。

## 2 四效果轴与四正式模式

效果轴是授权类别，不能把来源或敏感度塞入轴中。read 是当前允许投影的读取；model 是模型请求；write 是业务写入；outbound 是业务外传（工具 export/network 映射于此）。远程模型既有 model 条件，也必须核最终内容外发用途；不能因此免除内容门禁或将 model 开关视为所有业务 outbound 的 grant。

| 正式模式 | read | model | write | outbound |
| --- | --- | --- | --- | --- |
| 只读 | 当前获准投影，不扩大读取范围 | 独立 model 设置与权限，不因只读自动获得联网/披露许可 | 只草稿/预览，不提交 | 不执行业务外传 |
| 每次询问 | 当前获准投影 | 需授权请求确认；旧 grant 复用待 D01b | 当前意图确认 | 当前目的地与数据范围确认 |
| Auto（新装默认） | 当前获准投影 | 已冻结确定性 low 自动/high 确认/禁止拒绝 | 同样按版本化风险规则 | 同样按范围与版本化风险规则 |
| FullAllow 全部允许 B | 当前获准投影 | 当前任务/scope/权限/用途内免额外风险问 | 合法范围内免额外风险问，包括 high、taint | 含此前未用网站/API，免首次端点及额外风险问 |

FullAllow 对 none/personal/commercial 在有效任务及既有权限用途内默认允许；不要求逐对象授权或预选端点。实际目标、参数和载荷摘要仍固定并落账。四档与新装默认 Auto 已定，不重新询问。新装初始化不等于升级已有库的缺失旧配置。

legacy standard/readOnly/custom 不仅改名：先保留旧兼容行为、四维开关和 policy revision，显式主动选新档才进入新版 ModeGrant 语义。缺失旧配置走 legacy_standard；损坏/写锁存 fail-closed，不静默 Auto 或 FullAllow。旧 readOnly 保留禁 write/outbound 和独立 model；custom 不从开关自授 grant。once/task/conversation/timed/always 保留 scope、tool、destination、task/conversation、到期、次数、撤销与旧 outbound 会话上界；旧 outbound 不能变 always。完整三档×四轴×五时长映射、旧 grant 复用和新版真实期限待 D01b，受影响样本 blocked_contract。

## 3 最小判定顺序与 decision table（提案）

Rust 对当前事实确定性计算；客户端或模型的 approved/low/classified 标签无权代替宿主判定。先核计划、真实权限/用途/身份/能力/版本与内容门禁，再按模式处理风险；实际消费与派发仍遵守原子账本合同。多失败时的稳定原因优先序及 wire 编码待 M03；不能由优先显示一个原因掩盖其他门禁。

| 当前事实 | 分类/执行判定 | 允许的下一步 |
| --- | --- | --- |
| 计划/参数/scope/当前权/身份/TLS/真实能力缺失，已撤权，明确禁用途，业务非法，CAS 冲突或服务硬限制 | 所有档停止；保留可信硬原因 | 修正材料、换有效环境或重规划，普通确认不能解除 |
| 受影响能力存在有效 capability_hold | 对应路径不准入；已派发继续核对 | 只按工程修复与独立证据解除 |
| 当前实际值命中 credential | 原始凭据不得进入模型上下文、业务工具/分享正文或日志；本机name业务正文亦不承载秘密 | typed拒绝并保留非秘密原因；正常认证只走绑定专用通道 |
| 模型请求/业务外发的必需单元为 unreviewed，或该出口分类检查未完成/覆盖不足 | 不进入该模型/业务外发载荷；不是全部本机写入的统一禁令 | 该分类尝试缺覆盖terminal；新内容/规则可建新尝试 |
| 本机单字段name用途，整体外发Sensitivity域尚未覆盖，但当前用途最小必要声明/来源/实际ValueCheck及授权、CAS、业务与模式规则均有效 | 可按模式继续本机计划/提交，0模型/0外发；不等完整D01b或14条全域分类规则 | 后续外发仍须该出口完整分类；不将本机通过写成已分类/外发许可 |
| 本机name当前用途的actual-value credential检查、来源/字段证明或必要风险规则缺失 | 缺可信事实typed拒绝；合同/覆盖未定blocked_contract，明确当前用途缺口 | 不以普通确认绕过，不无限等分类，不用其他域未覆盖替代当前缺口原因 |
| read 且当前投影获准 | 可读；不附带写权 | 无需为普通 read 造 grant |
| 只读档 write/outbound | 不派发 | 草稿/预览；用户显式选新档后重验 |
| 每次询问，当前完整新计划，合成一次性确认有效 | 确认后仍重验执行事实，才可派发 | 参数/事实变更旧确认失效；旧 grant 复用未定则 blocked_contract |
| Auto，匹配已冻结 low/high/禁止规则 | low 自动；high 当前意图确认；禁止依冻结规则拒绝并记录其来源 | 规则不可用/未覆盖→blocked_contract；不默认永久 confirm |
| FullAllow，全部执行和内容前提有效，仅高风险/taint/新端点/建议 confirm/block/建议服务故障 | 免额外风险确认；风险只记录、展示及影响恢复策略 | 无风险评分也不隐形暂停；真实硬限制仍停止 |
| 仅已知 name=none 或 content_review=allow | 不构成 grant 或成功事实 | 继续核模式、计划、能力、用途和账本 |
| 同 intent 重投递、已派发 unknown、模式切换 | 不制造第二派发；unknown核原权威回执 | 不凭超时/notFound/换 FullAllow认定失败或重发 |

RiskDecision 最小语义继承 D 第6章：risk_class、reason_codes、matched_rule_ids、policy_revision、decision_digest；输入含动作、类别、影响范围、可逆性、接收者、来源可信度。具体 wire 只由 M03 定义。ModeGrant 和 RiskDecision 分轴保存，RiskDecision 本身不授能力。

建议可独立冻结 `RD-SUPPLIER-NAME-LOCAL-v1`：仅可信完整单 supplier.name 本机编辑，稳定真实新 intent，精确当前对象/选定工作区/单字段读写集，M02规范值合法，CAS与业务关联不变量已证，有效当前权限；最终用途为本机业务字段，无 model 请求或外传，无已知模型/外部派生来源、未知读写依赖或不可核事实。上述全部为已证且本机当前用途的最小声明、来源与actual-value credential检查有确定覆盖/版本并通过时，risk_class=low；不要求外发Sensitivity全域覆盖或A00全部14规则实现。规则结果只给 Auto 自动路径，不豁免硬门禁。taint/模型派生或其他动作不匹配本规则，不把它们永久判 high：Auto 对这些域暂为 blocked_contract，由 D01b 增加版本化规则。

首片 high 路由以明确版本的离线合成风险判定验证“Auto确认、FullAllow免风险问”，不是宣称已有真实 high 生产规则。禁止型风险规则与可信硬限制来源必须分别显示；仅风险性禁止/建议block不能在 FullAllow伪装成服务硬限制。

## 4 确定性供应商名称入口与合成 ModeGrant

用户完整名称编辑→domain_command→Rust确定性预览/计划→按模式与能力重验→CAS提交→真实 EffectReceipt。全过程0模型轮、0外部发送。最小实际值检查也不得为满足字段声明额外调用模型。

承接 M02 已定限定语义：所有新入口送完整 raw；raw UTF-16 长度≤2000→XML合法字符检查→trim→NFC→required及规范后≤200码点。新端不预trim以绕过 raw 或 XML检查。同规范名的可信真实新 intent仍 revision+1/独立 receipt；同 intent 双击/replay复用原回执，零第二写。不能只换 key 将旧 unknown偷变新意图。具体 Unicode/trim/NFC版本及跨端等价仍由M04/M05 oracle证明并作为M03门禁；本文不提供伪等价结论。

合成fixture上下文（提案，非产品默认期限）：虚构scope S、supplier UUIDv4合成S1/rev1、host任务T、intent I1、固定假时钟t0；ModeGrant在t0可信创建、expires=t0+10分钟，绑定scope/action/target/plan摘要和当前mode/authority版本；max_uses=1，撤销=false。FullAllow的有效模式可为真实新意图重新派生受约束单动作能力，不把一次性fixture耗尽误说成产品每操作需人审。消费与dispatching须按同事务合同验证，具体M03编码待定。t0+10分钟前有效，等于/晚于到期停止；计划变更/撤权/模式版本变化按当前事实重验。每次询问的合成确认来自可信固定组件，不接受renderer/model布尔值。

10分钟及一次消费仅为有限测试输入；新版产品期限尚未冻结。真实期限尚未明的行为记录 blocked_contract，不把 fixture 常数推广成默认。

## 5 分类、内容复核与能力暂停

固定D第一册L798–801区分unreviewed禁模型/业务外发与credential正文禁用，第二册L946–947明确unreviewed“先不外发，包括模型请求”。原def5草案§3把两者合并为统一业务正文门禁过宽，本delta拆开；此处不修改原A00输入或两册。

Sensitivity 只有 unreviewed/none/personal/commercial/credential；来源、taint、verification、classification attempt、模式和效果回执独立。字段 none 不是grant。模型生成 name 必须字段声明 ∧ 实际新值宿主输出规则/credential检查 ∧ 来源限制 ∧ 当前用途。干净且完整覆盖值可继承字段类别，不永久unreviewed；采用/编辑模型建议保留真实模型谱系。只扫描旧值/用户输入不算输出检查；参数、编码、嵌套内容或最终载荷变化令旧证据失效。

凭据不得进入模型/业务正文、日志、通知或诊断。认证走可信连接credentialRef与绑定身份/端点的允许header或专用认证通道，不能让模型选秘密、跨服务复用或重定向；不能退回业务正文。模型/业务外发用途的必要内容未覆盖、疑似/失败/截断等保持unreviewed，本次分类尝试 terminal（例如A00拟定no_coverage），给非秘密原因；没有无限classification spinner/定时空转。新内容或真实新规则可建新尝试，不原地改写旧失败；FullAllow/确认/时间流逝不能完成分类。

本机纯用户name编辑只依赖本用途最小规则：可信字段声明、完整真实用户输入事件与可核来源/限制、规范后实际提交值的本机credential检查及内容版本绑定，连同当前权限、CAS、业务条件和适用模式风险规则。ValueCheck在此仅表示当前用途的实际值检查语义，不是新增DTO/enum，也不表示已完成全域Sensitivity分类。检查完整且无凭据信号可在这些前提有效时按模式本机保存；整体Sensitivity尚无外发覆盖不能单独阻此路径，也不能把结果补标none/授grant或许可外发。实际检查疑似/失败/截断/本用途无覆盖，或未知来源/继承限制无法核验仍停止：已知不合法事实typed拒绝，必要合同未冻blocked_contract，明确缺口并结束本次检查；普通确认、FullAllow及等待均不能补事实。没有模型新输出的纯编辑不等模型输出规则；模型派生/其他Auto域仍按各自最小必要检查与未冻合同处理，不洗来源、不永久默认confirm。

capability_hold对象是能力路径＋构建/合同版本，针对授权证明、撤权传播、越界投影、账本/回执/原子性异常等已证工程阻断；持久active→remediation_ready→verified→cleared，尽量隔离受影响路径。高风险/taint/建议服务不可用不能单独触发。重启/换档/用户批准/content_review=allow不能清除；需要修复或隔离、反例、非作者复审与当前事实重查。

content_review对象是本次model请求或工具效果的plan/payload摘要；过程与allow/confirm/block结论分开，不授grant、不清hold、不证明效果成功。Noop reviewed=false不可展示已实质审查。FullAllow纯风险意见或建议服务异常/超时不加问、不无限等待；确实必需授权/账本/内容覆盖事实缺失才停止并明确缺口。可信reason/evidence全映射及旧reviewer双路径由D01b/D04/ADR合同完成，不在本文冒称全冻结。

## 6 正负 fixture 目录

全部 draft/not_run；仅扩既有 V131-T01/T02/T03/T09 与 V12-A4 子场景，不增加52主case。表ID是本文局部引用，不另建主验收号或产品schema。A00原14规则、29子case仍原状态。合成输入以生成器/固定非秘密文本表达，不引用真实库/凭据/模型。

| 局部ID / 既有主case | 正/负输入 | 待验证预期 |
| --- | --- | --- |
| A01 / V131-T01,T09 | 完整本机name，四档同scope/rev/合成有效能力；提案最小low | 只读0写；每次询问可信当次决定后1写；冻结low的Auto1写免问；FullAllow1写免风险问；所有0模型/0外发 |
| A02 / V131-T09 | 假high、taint、新端点，执行事实与分类完整 | Auto仅冻结规则按high确认，否则blocked_contract；FullAllow假model/工具最终传输零风险/首次问；无真实网络 |
| A03 / V131-T01,T09 | grant到期、错误scope/对象/身份、TLS/系统/服务硬限、CAS冲突、撤权 | 四档相应停止，无写/发送/成功回执；FullAllow不解除 |
| A04 / V131-T01 | 已检查plan v1，提交name/目的地/权限版本变v2；伪approved | 旧证据/能力不能签新参数；重新校验或停止，0第二效果 |
| A05 / V131-T01 | 同intent双击/重启、丢响应；真实新intent同规范名 | replay原receipt/零第二写；可信新intent独立receipt/revision+1；unknown先核对，不用换key补发 |
| A06 / V131-T09 | legacy三档×四轴×五时长、缺失/损坏/撤销/外传会话超界 | 保持旧限制、损坏闭合、不延长、不升级；未定完整映射blocked_contract |
| A07 / V131-T01,T02/F08,T09 | 完整可信纯用户name；外发分类域未覆盖，本机用途actual-value检查complete/无信号且所有必要事实有效；再分别删除本机检查/来源/低风险规则或给疑似秘密 | 前者按已冻结模式本机写0模型/0外发，不等14规则；后者当前用途typed拒绝或blocked_contract、0写，不洗来源/补none/默认confirm；FullAllow亦不补缺检查 |
| F01 / V131-T02/F01,F10 | 假模型name干净＋声明＋actual output complete，FullAllow/Auto | 分类可none且保留来源；FullAllow假双出口可用；Auto域未冻blocked_contract，不能抄FullAllow金标 |
| F02 / V131-T02/F02–F07 | 合成credential canary/疑似/无覆盖/未知字段/旧值扫描/检查后改payload/失权来源 | credential禁正文；unreviewed禁止相应模型/业务外发，当前本机用途缺必要检查另按A07停止；最终假model/工具载荷与日志无禁单元；none不能降来源类 |
| F03 / V131-T02/F08,F09 | 用户完整确定性编辑；或采纳假模型建议后改一字 | 首者直Rust0模型；后者保留模型来源并新版本重查，不改标用户原创 |
| F04 / V131-T02/N01–N03 | no_coverage后等待/切档/确认；然后真实新规则或可读新版本 | 原尝试terminal、不派发；新证据才能建新尝试，无永久封锁/无限等待 |
| F05 / V131-T03 | 正确绑定合成credentialRef header；wrong endpoint/redirect/正文插槽 | 仅合法身份认证通道；禁业务/模型正文和跨服务秘密，不回显canary |
| R01 / V12-A4,T09 | capability_hold后重启/换档/review allow；仅风险review confirm/block/unavailable | 前者锁存；后者FullAllow不额外风险批准/hold；必要事实真缺失给准确停止原因 |
| R02 / V131-T02,T09 | 普通用户文本按USER-TEXT-v1可分类但Auto外发风险域未冻 | 分类结果与动作分栏，动作blocked_contract；不得默认永久确认或静默低风险 |

每行抓取：固定P/D和实现SHA、输入/字段/规则/规范化版本、覆盖与attempt结果、真实合成来源谱系、scope/purpose与当前权限、mode/RiskDecision或blocked_contract、计划/参数摘要、明确测试期限、消费/撤销、intent/回执对应、库diff/写次数、模型/工具假payload捕获、确认与实际派发计数、安全投影及非作者证据。wire及digest域归M03。单独分类通过不是动作通过；假发送不是生产外发验收。

## 7 C-I-M 与独立冻结条件

C（阻断合同冻结）：最小RD规则是否接受及覆盖/版本、ModeGrant证据与消费原子边界需非作者核对；M02修订delta需独立审查；D03a恢复引用与SPIKE-01真实Android库加载证据缺失时M03不能冻。本文尚无非作者复审，不冒称C0。

I（后续实施/验收）：14拟定分类规则真实实现、actual output检查/规范化域/误报漏报说明、model与工具全链最终载荷、持久hold/review可信理由映射、真实scope/CAS/账本/回执接线均未提供。完整D01b是W4真实权限开放前置；本首片草案不能替代。

M（需澄清或补齐的记录）：完整legacy映射/期限/custom编辑、普通用户文本Auto风险、taint及其他Auto域、精确Unicode版本与跨端等价、合成fixture期限的最终表示仍open；不重开已定四档/新装Auto/FullAllow B。

可独立冻结出口：Leader B指定非作者对精确本提交审查，确认最小name低风险规则及正负断言、有限fixture能力期限与不升权边界；M02限定领域修订证据就绪；D03a/SPIKE-01协调对应引用；M03统一schema前完成真实Android加载及Normalization等价证明。只冻结已覆盖最小规则和离线合同，未知项保留blocked_contract，不借此宣布全D01b或52验收完成。
