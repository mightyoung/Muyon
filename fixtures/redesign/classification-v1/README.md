# A00 classification-v1 合成输入与预期目录

状态：draft。14规则全部 `proposed_unfrozen`；29个原 V131-T02 子case全部 `not_run`；原52主case仍 `not_run`，新增主case为0。77个variant只是29子case内部输入矩阵，不是77项已运行测试。本目录没有分类engine、生产DTO、JSON Schema、Rust实现、真实模型/外发或运行验收。

基线commit `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`；P `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；D `58fe9c62612d74a973614c41677e62a54332e6d6`。已审D01a输入 `99c4d779bb5b94e3388637228f42869d6e81152d`。`manifest.json` 固定来源路径和逐字节SHA256；原输入字节不变。

## 文件与阅读方式

`manifest.json` 是fixture索引；`rules.json` 保留A00原14规则的拟定ID、来源/范围与待冻结状态。`U01.json` 至 `N03.json` 各对应原目录一个子case，完整列表以manifest为准。局部fixture记录键只为审查合成材料，不用于生产序列化，M03仍唯一决定正式schema。

每个variant分别列出合成输入、可信来源事件假设/继承限制、当前内容与检查版本、当前purpose、规则覆盖假设、actual-value检查假设、有限模式授权假设、执行硬前提以及待观察预期。`*_assumption` 不代表已经注册规则或运行检查；`*_expected` 不是实际状态枚举。`not_observed_not_run` 明确没有实际载荷抓取、数据库diff或权威回执。ValueCheck只是当前用途实际值检查语义，不是另造产品类型。

| 原子case组 | 数量 | JSON文件与范围 |
| --- | --- | --- |
| U | 3 | 用户文字、命中/疑似、未执行/失败/截断/未知分类 |
| A | 2 | 第2页独立用途与整份附件完整任务 |
| P | 2 | 工具schema范围与来源伪装 |
| D | 2 | 派生商业来源继承与历史失效 |
| M | 2 | 元数据出口与受控模板/动态槽 |
| F | 11 | 实际生成字段值、版本与模式/执行门禁 |
| C | 4 | 裁剪、原意、版本关系留存与重放 |
| N | 3 | 无覆盖终态、无效“补审”、新内容/规则新尝试 |

## 模型字段的合取条件

F01的合法生成name有确定路径：可信host固定字段 `supplier.name` 及P声明版本提供基础类别；假输出的实际新值经本机规范化后，必须在当前输出规则覆盖域完成credential检查，证据绑定实际新内容/来源/最终参数版本。还要保留来源限制并核当前用途、真实授权、业务、CAS与账本。字段none与输出检查不可互相替代，模型自报标签均不提供证据。

F01同时列本机name、模型请求、业务外发三种purpose。候选载荷eligible仅在其完整合成前提成立时成立，未实际派发。干净已覆盖生成值可继承字段基础类别，不因模型来源永久unreviewed。F02命中实际值不能被字段none覆盖；F03缺当前provider/schema/值类型输出域即本次终止；F04未知字段/枚举闭合拒绝；F05只查旧值/用户输入无效；F06最终参数/编码/嵌套值/序列化变更使旧检查失效。F07商业来源复制进none字段仍继承commercial与更窄用途，真实禁用途/撤权不能被FullAllow解除。

F09采纳并编辑保留模型来源，新版本重查可继续；F10分类与Auto low/high/禁止/未冻风险规则分开，四分支仅给离线规则路由的假设预期，不宣称真实模型字段Auto规则已经冻结；未冻写 `blocked_contract`，不默认永久confirm。F11仍核scope/CAS/计划/幂等；replay复用核实原回执，不制造第二效果。

## 本机与外发适用范围

依据固定D第一册L798–801、第二册L946–947，以及 [根适用澄清](../../../docs/tasks/redesign-kickoff-20261014/A00-APPLICABILITY-CLARIFICATION.md)：unreviewed禁止进入模型请求/业务外发；不能泛化为所有本机业务body。credential原始值禁止模型上下文/业务正文/日志，合法认证专用通道另核，不能借模式豁免。

F08完整真实用户name无模型输出，直Rust、0模型轮、0外发。当前用途最小可信字段声明、真实来源/限制和规范化后actual-value credential检查完整，再通过权限/CAS/业务/适用模式规则时，本机路径不等待14条广域规则或全D01b。整体外发Sensitivity尚未覆盖不单独封本机，也不因本机通过就授外发权或补标已审。当前本机检查缺失、未知来源或必要合同缺失仍typed拒绝/blocked_contract，不能洗来源、凭none授grant、无限等待或以确认补检查。

FullAllow合法当前用途不依赖Auto风险规则，F01/F08相应正例明确保留 `auto_risk_rule=unfrozen_not_required_by_FullAllow` 且可eligible；同样FullAllow的actual-value检查缺失仍停止。Auto尚未覆盖域保持blocked_contract。10分钟合成ModeGrant期限只是fixture输入，不是产品默认期限，grant/policy实际表示仍待M03/D01b。

`expected`中body允许标记仅说明该variant当前purpose下候选材料可否使用；不构成跨用途许可，也不能从某外发负例推导全局本机写禁令。真正执行还需当前授权、能力、身份/TLS、CAS、业务与账本；classification/content_review/字段none都不是grant或成功回执。

## 符号秘密与终态

凭据场景不含真实key或秘密正文。`opaque_secret_refs` 中 `SENTINEL_CREDENTIAL_01` 是符号元数据，检查命中也是离线假设；审查器或后续测试器不能把符号本身当成功检测的真实凭据，不能将其复制到payload/log来声称全链无泄漏已通过。未来runtime harness必须由独立真实实现提供覆盖证据，本文不定义字符串扫描或镜像算法。

N01/F03无覆盖终止本次尝试，内容仍unreviewed；不无限spinner/空转重试。等待/切FullAllow/普通确认/模型标签不能补覆盖。N03真实可读新内容或可用新规则可建新尝试，旧失败不改写，不永久封锁。C01裁剪需要新内容版本重分和任务完整性证明；C02不能裁掉必需name后声称完成；C03/C04只保留获准版本关系与最小元数据，不额外留秘密原文/差分，曾使用不等于当前可用。

## 结构完整性验证与真实验收缺口

在本目录运行 `sha256sum -c SHA256SUMS` 只验证文件字节。逐个JSON语法、29唯一case ID/77唯一局部variant、14规则引用、源输入哈希及必需描述字段检查只验证fixture结构，不能记为classification/value-check/mode/transport/数据库测试PASS。本次没有运行任何生产分类器或复制实现算法来刷PASS。

未来执行需精确实现SHA/命令、规则与Unicode/normalization版本/覆盖、宿主来源与当前权限、actual新值检查及最终参数摘要、实际模型/工具载荷捕获（或证明纯本机0调用）、权威回执和库diff、日志投影及非作者审查。M04/M05规范化等价、D03a及SPIKE-01真实Android库加载证据与M03单源编码仍为门禁；本目录不冻结M03、D01b、ADR或52主验收。
