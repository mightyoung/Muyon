# v1.3.2 第二批隔离合同实验

状态：实施与非作者审查在途，尚无本批组合 CI 或合入结论。唯一集成人 Leader B。

## 固定前置与边界

首批终态报告 `8f8edf95983476a8963ea4cb35ee0a3b948aa862`，已合入基线
`1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`。M02合同
`2fd91b03a7b5f0888c1e11ab0ba559a580e970d0`，D01a合同
`99c4d779bb5b94e3388637228f42869d6e81152d`，D03a合同
`40f3cddb6e62baa2374bde288120d2385cb14c3f` 已进入首批。
依赖允许 M02 后、M03 前执行隔离合成语义实验；完整 wire/DTO、摘要、类型、ID、时间及规则冻结仍归 M03。
实验不是产品实现、真实授权、真实发送或 Android 加载验收。

原分类输入 `7a8128ca86c583b0bbf1191c4baa4f3e732ca547` 的29 case/77变体及14 proposed_unfrozen规则，
原恢复输入 `55480f06490983a54e38908b043b06b4b02df451` 的19组72场景原字节、not_run历史及actual/golden空值保留。
52主验收不因实验自动通过。未提供真实输入事实的场景必须记录 partial_experimental 或 not_run 与具体缺口。

## 独占 writer 与审查

| 作者/任务 | 独占写范围 | 非作者审查 |
| --- | --- | --- |
| redesign_d01a_contract | experiments/redesign/d01a-contract/、fixtures/redesign/classification-purpose-v2/、docs/tasks/REDESIGN-D01A-EXPERIMENT-20261014.md | redesign_m01_review |
| redesign_d03a_contract | experiments/redesign/d03a-contract/、docs/tasks/REDESIGN-D03A-EXPERIMENT-20261014.md | oc_triple_runtime_verify，仅本批恢复审查 |
| redesign_m02_contract | 仓库外SPIKE01只读inventory，无仓库writer | B核查报告 |
| B | 本任务书及docs/tasks/redesign-experiments-20261014/组合登记 | 两路固定SHA审查后组合 |

全部实验工作区由固定基线新建，旧作者分支、工作区及其它writer保留。
不修改 apps/packages、产品数据库迁移、依赖或 CI 工作流以掩盖失败。

## 可执行计划

1. D01a先修I03：材料资格只属于当前purpose，非当前用途为not_applicable；资格与模式/dispatch权威分轴。
   可信字段声明与实际当前新值覆盖同时成立；未知来源、旧证据、凭据、无覆盖均有负例。
   验证只读/询问/Auto/FullAllow、缺Auto规则与缺ValueCheck的区别，不注册或宣称14生产分类规则。
2. D03a先以独立输入事实实现恢复reducer与临时合成持久store。
   验证四字段cursor域、projection与durable水位原子边界、真实子进程崩溃/重开、bounded buffer、
   旧epoch展示与真实迟到receipt区分、unknown零自动重放、PendingInput保留及新intent隔离。
   实验SQLite表只作验证接缝，不是产品schema。
3. 两路DUT只接明确input事实，不接expected/caseID；oracle在actual生成后独立比较。
   各自先留真实RED，再GREEN；至少两项语义逆变异必须失败，恢复后重跑GREEN。
   非作者从不可变fullSHA复跑，进行expected改动负对照，核原fixture字节、计数和未执行项。
4. SPIKE01只读盘点已有工具、runner及真实加载缺口；不安装、不下载、不启动设备、不建凭据或购买资源。
5. B仅组合已审查交付，运行两路轻量命令与保存范围/历史校验，再决定是否推独立组合分支执行精确SHA CI。
   新失败或基线前进先记录影响；无C0、缺变异证据或CI未终态不得宣布可合入。

## 停止条件与报告

DUT读取oracle或caseID结果表、expected值变actual、原not_run改PASS、实际秘密入日志、产品schema提前冻结、
越界改作者文件、真实模型/用户库/Android操作均立即停止相应路线并回报。
输入缺receipt/digest/body/签名等权威事实只保留未验证边界，不从expected补造。
M03仍blocked_contract：Android Rust真实加载/回调/释放/错误、双传输语义/摘要比较、Unicode实现等价及唯一schema未齐。
终态报告必须包括作者/组合完整SHA、实际命令与exit、RED/GREEN/变异计数、独立审查、精确CI和剩余门槛。
原始日志留仓库外；本批报告不再更新或复跑旧OC专项。

## 固定交付与组合轻量终态

D01a `ad548c35552fba74946827bc9cb5068d9ccc128d`、D03a `eef7561289421c58e88896fa69c868403ca1d3c5`
分别取得非作者C0，仅接受实验范围。审查原文与safe proof在本任务配套目录，未导入原始日志。
B新组合工作区独立执行D01a 33 tests、D03a 24 tests均exit0；两路各3语义逆变异子进程均exit1，
恢复后源码/工作区干净。D01a矩阵61partial_experimental/16not_run/0局部差异；expected-only负控exit1且77actual不变。
D03a矩阵63partial/9not_run/0完整场景PASS，274matched/0mismatch；非作者72行oracle/IDs/golden扰动不改变actual。
两路包含真实AssertionError RED，额外SQLite故障测试不算原72场景。I03只在实验表示落实，不冻结产品DTO。

精确命令、exit、计数、源码范围及日志hash见[组合轻量proof](redesign-experiments-20261014/combination-preci-proof.json)。
相对1dc产品/CI/依赖/原合同/设计/v1输入diff为空，v2三项SHA校验exit0。原29/77、19/72、52主历史全部保留。
独立组合候选将正常推送触发既有CI；此登记时CI仍pending，不冒称终态。既有CI不包含新Python实验，
其Flutter/Doctor/Laya门禁只作为该候选整体回归证据，新接缝由以上实际轻量命令及非作者复验支持。
本批不执行develop/main合入，不改作者分支。SPIKE01仍只读盘点，缺Android/Rust工具链与真实native load，M03 blocked。

## 用户最新开发顺序调整（2026-10-14）

设备验证后置；不再以缺 Android runner 暂停全部后续研发。
按[四路可逆研发补充计划](REDESIGN-DEVICE-DEFERRED-PLAN-20261014.md)开展 Rust 纯领域、Rust 恢复、
Electron 界面/mock 和 Kotlin/Compose 界面/mock。原实验及 fixture 历史、授权规则均保留。
上文 SPIKE 只读盘点/工具缺失为历史状态，不覆盖后续独立 H1 修复与 Linux/JVM 实测。
M03 仍 blocked_contract，Android actual load NOT_RUN；临时接缝不冻结 DTO，设备与发布门不取消。
