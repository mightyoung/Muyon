# 首批完整候选final registration独立只读复审

固定候选 `f0ca8fd3e11c1a7ebd3cffdfc3875cdc4365c5ab`，branch `task/leader-b-redesign-first-batch-20261014`，worktree `/workspace/Muyon-leader-b-redesign-first-batch-20261014`；本delta相对bc5b2c37，整体历史/字节边界相对产品01e56cc与设计58fe9c核对。

**C=0，可进入B的正常推送及精确候选CI阶段。** 本结论为fixed candidate文档/输入/函数参考组合准入，不是develop合入成功、candidate CI通过或M03冻结。唯一集成人仍B，未提出额外用户决策/审批。原M04/M05独立47调用结果沿用已完成报告，本轮未重复运行；root组合fresh rerun只按其登记范围读取，不冒称本轮再次独立执行。

## 已核组合范围及来源保全

相对bc5b共57路径：49个作者交付文件全部与固定来源字节一致（M04 8c599的6项、M05 962的5项、分类7a8128的34项、恢复55480的4项），另8个root登记/已交审查文件。三份Draft合同及任务书6文件亦分别等于已审M02 2fd、D01a99、D03a40固定来源。没有共享产品writer或源码/config修改。

相对产品01e56cc已有文件仅2处修改：ADR0001仅append，HANDOVER仅prefix；各历史原正文完整保持原字节。原95设计文件和421 intake的8个不可变文件（来源内容/SHA256SUMS/root证明）逐字保留，原95目录/附件未追改。旧C6两源没有带入产品实现，登记保留failure并明确排除；其CI不会代表候选失败或成功。

M01-STATE旧M01/A00/M02/D01a/D03a running记录已换为具体已交付/已审限定状态，记录实际full source、branch、writer和独占路径；M01 root登记活动状态只是正在准备集成。旧作者源任务书自身“待非作者”等保留其当时事实，root终态登记覆盖当前接收结论，不误称作者仍修改原合同。23旧null writer仍只是尚未分派产品实施，由B按阶段custodian预留，不推断共享文件空闲。

## 证据层级、CI与I项

- **有限Dart层：**32pass/14partial/8not_run只属于固定Dart normalizeText/Supplier构造器参考；47调用、39独立预期、0差异与已审M05原报告一致。private guard/controller/schema/完整dispatch、CAS/scope/分类/授权/回执没有被算通过。依赖Unicode8.0声明不证明Rust/Android/双传输等价。
- **未运行分类/恢复：**14规则proposed_unfrozen；分类29case/77variant均not_run；恢复19group/72scenario均not_run，actual/golden null；52主验收仍not_run，局部记录不新增主号。三目录SHA256SUMS共4+32+2项全通过，这只是完整性检查。10份独立review保存文件hash全匹配状态清单。
- **I03保留准确：**root首批登记、状态与分类delta审查报告都限制bodyflags为当前purpose候选材料资格，与action_result及授权分轴。非当前true flag不提供任何许可；实际runner/M03前必须改为单current-purpose资格或非当前not_applicable。该待细化项可在Draft输入阶段保留，不能带着多用途true解释进入执行器或编码冻结。它不重开FullAllow已分类合法动作、不推导全局本机写禁。
- **精确CI仍待：**成功run38488260486明确绑定bc5b fullSHA，仅覆盖当时入口/合同候选。root未将它标为f0ca8fd的success，也未称包含后续fixtures/scripts。f0ca8fd最终注册审查及精确candidate CI在固定快照时pending；B应正常push后核checkout exactSHA与完整CI终态，再按唯一集成门禁决定develop，合入后另核CI。
- **M03仍blocked：**D01a实际值/模式和D03a恢复runner未执行，完整入口/状态与Unicode跨端等价缺证据，SPIKE-01真实Android加载/回调释放/错误/双传输语义摘要缺结果，单源schema/编码未冻结。原工具链缺失登记不能用旧Flutter CI、fixture或静态审查替代真实Android gate。

## 本次实际检查与支持证据

实际只读运行固定source→candidate字节比较、两历史正文startswith/endswith保全检查、95设计/8 intake/6 Draft来源比较、分类29/77/14、恢复19/72及状态null检查、38项fixture哈希、10review hash、两路径基线修改范围及`git diff --check`。目标worktree干净。没有再跑47调用、真实native/model/data/device、push、merge、安装或产品修改；原始日志没有进仓库。

机器证据 `proof.json`，检查脚本 `verify.py`。本C0允许组合材料进入精确候选验证阶段；I03和Runtime/M03未满足项不因此闭合。候选CI成功应只作为该提交实际命令的结果，不能提升为分类/恢复/52新架构验收完成。
