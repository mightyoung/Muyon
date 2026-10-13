# REDESIGN-M02-SUPPLIER-NAME-20261014

状态：M02限定领域三项决定已定，本修订待非作者delta审查；其余`blocked_contract`项保留，非M03冻结或首片产品实现。日期：2026-10-14 北京时间。

授权来源：用户按 Muyon v1.3.2 开工并交由 Leader B 派发/审查/唯一 develop 合入；父任务明确委派 M02 首片领域合同。真实 writer：`redesign_m02_contract` agent。Leader B responsibilityB custodian/唯一集成人；产品 writer 尚未分派。独立 worktree：`/workspace/Muyon-leader-b-redesign-m02-20261014`；branch：`leader-b/redesign-m02-supplier-name-20261014`；起点：`421e7332807d0f8a2f7a6a36819601dcad442130`。

交付仅两个文件：

- [供应商名称合同草案](../contracts/redesign-v1.3.2/supplier-name-contract.md)
- 本任务登记 `docs/tasks/REDESIGN-M02-SUPPLIER-NAME-20261014.md`

固定事实：产品 SHA `01e56cc2d729dab70e1b1def05c3aa93b28f421a`；设计 SHA `58fe9c62612d74a973614c41677e62a54332e6d6`；A00 intake 随起点提交。未发现本仓库/父目录 AGENTS.md 或本地 .agents/skills；cloud using-superpowers 明确对已派发具体任务的 subagent 不适用，不引入附加审批或实现流程。其他已有 worktree 未改动。

核查结果：现行名称要求合法XML字符，trim→NFC→最多200 Unicode码点，工具另有原始字符串2000 UTF-16长度限制；null/空白/false/数组/缺省分入口核对。旧页面完整payload save无 expected_version，工具有scope快照+CAS。业务回执同事务提交，但handler先检查selected当前性再查receipt；恢复须只读查权威回执，不能把unknown自动重发。合同包含完整P路径/行号、旧目标差异、确定性0模型链、合法再次意图与重复提交、四正式模式/legacy不升权、A0014拟定规则和29not_run边界、模型字段类别与实际值检查合取、正负fixture语义与golden字段需求。

验证：引用产品目录相对固定产品SHA的git diff为空；静态核对真实校验/读取/写入/授权/回执代码。提交前检查仅指定两文件、`git diff --check`、固定路径和行号可定位。未写产品代码、schema、镜像实现的tests，未运行全8 CI或主验收；docs提交允许 [skip ci]，CI与入口switch由Leader B统筹。

尚未闭合：D01a最小模式与风险样本/期限、D03a恢复与投影表示、SPIKE-01双传输及实际Android库加载、M03同源schema/编码/Unicode差分、Normalization数据版本/实现等价的M04/M05 oracle证明。完整旧模式映射/期限与真实分类出口归D01b。未定case标blocked_contract，不默认永久confirm、不将legacy_standard标Auto，不声称测试通过。没有实际Android库加载证据不得冻结M03。

修订依据：原提交`642a939846a8f87e1fc8872142baa5ab755e1d02`获非作者[C0复审](/workspace/reports/redesign-m02-independent-20261014/REVIEW.md)，Leader B明确授权冻结三个领域决定：新端完整raw value进Rust且raw UTF-16 code units≤2000；统一XML check→trim→NFC→非空且≤200 Unicode码点；可信同规范名新intent仍revision+1及独立receipt，同intent重复不再写。独立readonly receipt恢复按当前scope/purpose最小投影保留，不弱化旧snapshot selection guard。补N07旧catalog_form VT/FF预trim与新端原raw拒绝差异，R03a/b/c同值新意图正例/重复与伪重试负例；仅目录、全部not_run。精确Normalization版本和实现等价留M04/M05 oracle验证及M03冻结前要件，未声称Unicode跨端实测一致。原642未改写，本delta另提交并交非作者复审。

边界：无main/force/delete/deploy、新凭据、支付、真实数据、模型/设备成本、push/merge；未修改M01、原两册/ADR/产品/Rust/Android/Electron或他人文件。交付正常本地文档commit，最终fullSHA由writer回报，非作者review及唯一develop合入由Leader B处理。
