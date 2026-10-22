# D01a/D03a coupled非作者只读复审

D01a固定 `def5fac074e8f6173dc42cf0d8f54cdcd9b3c377`，D03a固定 `40f3cddb6e62baa2374bde288120d2385cb14c3f`，均从c3d937新建。输入领域决定M02 `2fd91b03a7b5f0888c1e11ab0ba559a580e970d0`已有独立delta C0，该结论仅适用于限定领域语义。父任务集成0ec2159记录不替代本两源非作者审查。

审查只读四文档、必要P/D固定源锚点，报告仅写仓库外；未改作者、原书、M01/M02、ADR、任何产品或旧worktree。没有真实库/native/model/设备或程序测试，也未重复A00盘点。

## 结论与C/I/M

**草案接收范围C=0。D03a恢复语义可作Draft输入；D01a最小规则冻结前必须补清I-01的本机用途边界。** C表示阻断本次文档intake，I表示限定合同冻结/下游工程门禁前必闭合，M表示记录或后续可执行化注意。静态可审不代表已执行/已冻结M03。

### I-01：拆开credential正文硬禁与unreviewed外发硬禁，明确离线最小覆盖

D01a `authorization-minimal-contract.md:41`将“credential，或unreviewed/检查未完成/覆盖不足”合并成“禁进入模型或业务正文”。固定D第一册开头决定、§6及A00区分credential禁止模型/业务正文与unreviewed可信分类前不外发；该合并表述使本机业务写也看似必须全部可信分类，否则一律禁止。`RD-SUPPLIER-NAME-LOCAL-v1`又写“内容覆盖满足该用途”，却没有逐项列明本机最小用途覆盖，容易把后文14规则完整实现误当离线首片前置。

建议精确修订：credential单独保留模型/业务正文硬禁；unreviewed/检查未完成/缺覆盖的外发、模型披露路径停止；本机确定性name更新必须单独列明所需最小实际值检查、字段声明、真实来源/版本/用途覆盖，缺其中必要证据只阻受影响路径/具体case。普通确认与FullAllow不补出缺失事实。最小可冻结集合应覆盖原raw与规范后本次实际值、字段/规则版本、来源谱系和内容变更使旧证据失效；不能字段none=检查完成，也不能用户编辑模型值后洗成原创。要求最小必要检查，不等全部14规则、完整D01b或真实模型出口；完全没有相应用途规则时保留blocked_contract，不能以无须完整14为由跳过检查。

补一对限定fixture：干净的可信纯本机完整name、该最小用途覆盖有效可走Auto low/FullAllow零额外问且0模型/0外发；同raw实际值检查未执行/覆盖不足时具体路径blocked，不能用name=none、人工confirm或输入来源标签代替。此修订不要求新增主编号或重开用户已定模式。

这是草案明确化的必要条件，建议作者出限定delta再非作者只读核对，**当前不将D01a最小RD宣布已冻结**。

### I-02：coupled冻结与M03前置仍需真实证据

D01a提出的10分钟/max_uses=1是有限fixture输入，非产品期限，内容检查与风险结果/ModeGrant分轴正确。B可在I-01补清后接受限定RD与合成ModeGrant语义；还需具体版本化正负断言、消费/dispatching同事务边界和与D03a原账本身份的协调。D03a还需合成故障验证，快照与持久水位原子性不能由文档自证。

M03仍需D01a/D03a协调后的合同验证、M04/M05固定Dart Unicode oracle等价及SPIKE-01双传输/真实Android加载证据。两个草案没有资格分别固定wire DTO、字段类型、摘要域或JSON/UniFFI选型；完整legacy映射/真实分类与双最终出口归D01b后续对应门禁。不以当前没有23单元实施writer要求用户重新决定，由B按阶段custodian/文件预留安排。

### M-01：共同依赖结论可补终态记录

两源写M02 delta审查另记、不继承642 C0，是准确历史表达；现M02 2fd delta已有独立报告，B可在新终态登记中关联它，不追改两源历史。D01a/D03a任务的“未获非作者复审”在源提交时准确，本复审完成后由B新增终态，不能把源文自身当复审签字。

### M-02：局部fixture仍需可执行版本

D01a13行、D03a19组均语义目录，尚无runner/故障注入证据。数字/时钟/阈值/规范参数摘要等在M03/M04统一，128条/1MiB与10分钟只是候选/fixture。保留29分类not_run及52主验收不增、不通过；D03A局部编号不冒充新增主验收。

## 通过静态核对的核心语义

1. **四轴与FullAllow：** P `context.dart:59`是read/write/export/network效果，P policy `28–33`将export/network映射outbound，model是独立授权类别。D01a没有把model开关当所有外传grant。四正式档、新装Auto及legacy不升权一致；FullAllow合法高风险/taint/新端点无额外问，真实scope、identity/TLS、用途、系统能力、非法业务、CAS及撤权仍停。仅风险block/reviewer建议故障不能洗成硬限制。Auto缺规则blocked_contract，不永久confirm。
2. **最小RD边界：** §3规则只匹配可信完整、本机、单name、稳定新intent和已证读写集/当前授权，其他taint/模型派生域暂不匹配，不一律判high；RiskDecision不授能力、ModeGrant单独，字段none不提供grant。模型/外部来源不能用客户端low/classified标签或改一字洗白。I-01所述实际值最小检查清单须补明确后才冻结。
3. **cursor与隐私：** D03a继承D第一册`620–638`和第二册`254–274`，完整store/scope/stream/seq域，seq为许可投影流水位而非审计号；不同域不比较，合法过滤跳跃须核心可验证推进证据，不推断隐藏事件类别/计数。换stream/重启不重铸业务intent/key。
4. **快照与持久水位：** state+covered_through_seq原子取得，投影+durably_applied_cursor原子持久；received/applied/durable不互代。慢快照不盖新状态，同水位异payload隔离，权限收窄先清投影。boundedbuffer、缺口补拉/过期resync有界，不通过重新执行业务补历史。
5. **epoch与效果：** process_epoch只相等展示栅栏，旧展示无权覆盖新草稿，真实迟到EffectReceipt经当前连接/权限核原账本保存事实；原效果与当前对象revision分别呈现，撤读权不回显正文，cancel_requested不冒称cancelled/rollback，回执未知不预造receipt ID。
6. **PendingInput及unknown：** 送达身份与正文留存分离，重连/超时零新提交意图，正文持久只服从有效留存/草稿策略，未获准正文不承诺崩溃恢复。权威回执查询独立且不降低写selection guard；notFound/unreadable不等于未执行。可信明确新指令可另建关联意图、持续显示可能重复、原unknown保留，FullAllow不添风险弹窗。与D第一册`652–658`、第二册`739–745`一致，不与M02禁止“换key暗中重发”冲突。
7. **领域及运行边界：** raw UTF16≤2000→XML→trim→NFC→200码点与可信同值新intent+1沿用已审M02；跨端Normalization未验证。确定性更新0模型；假model/工具payload捕获是未来离线fixture，不是生产外发验收。

## 实际检查及采纳出口

两源各恰2个新增docs、共4预留路径；相对c3d937无其它改动，`git diff --check`通过，两worktree状态均空。P policy/context与D两册逐字相等固定blob，A00状态未修改；必要引用段已读，未复验109全部blob。可复现静态检查见`verify.py`与`evidence.json`。

B可接收四文件为可审Draft。D01a先补I-01的明确用途/最小检查与正负断言，读回非作者delta终态；再按限定RD和有限能力语义登记冻结范围。D03a可接入Draft来源，进一步协调同账本身份、当前许可投影、事务水位及有限fixture故障验证。M03在缺真实Android库加载/双传输/Unicode oracle或对应合同验证时继续blocked。现报告只有文档静态结论，无程序运行成功结论，入口ADR/HANDOVER写入不属于本审查writer范围。

## I-01补充：固定两册原文、来源A00与M02交叉核对

固定设计D `58fe9c62612d74a973614c41677e62a54332e6d6` 精确依据：

- 第一册L798：unreviewed“可信分类完成前不得进入模型或业务外发载荷”；L799：credential“原始凭据值不得进入模型上下文、业务工具/分享正文或日志”。L22/L53同样明确unreviewed不外发。L813真实用户提交只能证明来源/任务意图，不能替代凭据检查；L831已声明字段仍保留来源/用途与运行时凭据检查。L801“禁模型/业务披露”应按L798的模型/外发用途读取，不能扩大成所有本机写。
- 第二册L39：“unreviewed 在可信分类完成前不外发，模型不能自改标签；credential 明文不进模型上下文或业务正文”；L1709“未审先禁外发待可信分类”。L968无覆盖不应阻断所有无关输入，而需满足对应计划/必需字段或明确部分结果合同。
- 原A00附件 `Muyon-A00-Classification-Fixture-Catalog.md:51`确有同类过宽表述：“unreviewed 或当前版本未被规则完整覆盖 → 相应单元不进模型/业务载荷”。L44/L52的credential正文硬禁准确；L69–71也明确无模型输出不要求输出规则、默认直Rust。原ZIP附件及SHA256SUMS必须保持byte不动，不能以该来源审查材料指令覆盖用户已定用途。建议B新增单独A00适用澄清/errata，把L51限制为模型/外发载荷用途，本机name按最小当前用途检查与领域/权限/计划/CAS处理。
- M02固定2fd L100准确写“credential不能进模型/业务正文，unreviewed不外发”；L106纯确定性用户编辑无新输出不要求不存在的输出规则；L132仍为“credential禁正文或unreviewed不外发”。没有发现M02直接把unreviewed一律禁本机写，本次不撤回其限定领域delta C0；后续可关联A00适用澄清防止其目录引用被过宽解读。未知字段schema拒绝/缺当前必要值检查具体路径blocked不等于unreviewed全局禁写。

父任务已经认可这一边界并负责新增适用登记；本审查不写原来源报告、A00/作者文档、两册或产品。上述只是纠正适用范围，不重开四正式档/新装Auto/FullAllow或credential硬禁，不默授grant，也不将Auto其他未覆盖域默认low或永久confirm。
