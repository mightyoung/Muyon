# REDESIGN-D01A-EXPERIMENT-20261014

状态：实验接缝已实现并实际验证，待精确SHA非作者复审；最大证据partial_experimental，产品分类/派发及M03未完成。用户授权仅D01a admission/routing语义接缝，不开放产品调用。

新独占worktree `/workspace/Muyon-leader-b-d01a-experiment-20261014`；branch `task/leader-b-d01a-contract-experiment-20261014`；base develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`。固定结果输入 `8f8edf95983476a8963ea4cb35ee0a3b948aa862`（通过git对象读取，不把报告提交当受测产品SHA）。原D01a及分类writer/worktree均保留。

## 实施计划（先于接缝实现）

1. 固定读取v1 manifest、29/77、14proposed规则、已审99c4d合同、58fe设计与I03/根适用澄清；记录输入字节hash，原v1保持not_run不改。
2. TDD先测单current-purpose材料资格、非当前not_applicable与授权路由分轴；normalized实际新值/可信字段双条件、来源继承、版本失效、terminal无覆盖、local/outbound边界、FullAllow/Auto/hardlimit。初始空接缝需出现真实断言RED；不接受import错误当RED。
3. 用现成Python stdlib实现纯admission/routing逻辑与allowlist fixture adapter；DUT不得看到expected/caseID/variantID。外部driver调用后才读v1期望对比；不依据expected补stimuli。
4. I03派生purpose-v2记录仅改表达：一个当前purpose材料资格、非当前not_applicable；原29/77全部保留历史not_run。runtime结果最多partial_experimental，输入不足的分支not_run并列理由，不能把注入signal称实际credential扫描/整个case通过。
5. 执行完整独立实验unittest、fixture对照与expected-input anti-vacuity负对照、至少2个语义逆变异，保存实际RED/GREEN/mutation原始日志于仓库外；machine结果仅非secret范围、命令exit/counts及未覆盖门禁。
6. 本地正常commit并提交root和非作者redesign_m01_review精确SHA；B唯一集成。不push/merge/main/deploy，不改product/原合同/设计/v1/CI/sharedtaskroot，不安装/新依赖/网络/真实库/Android/model/MUYON_EVAL_REAL。

接缝边界：实际credential detector、Unicode跨端等价、完整14分类规则/来源issuer、权限/能力消费事务、payload序列化与实际发送、数据库/回执、恢复及SPIKE-01/M03均未由本实验实现。fixture的host_check_assumption_not_classifier_result仅是信号输入；不能升级52主case或29wholecase的验收状态。

## 实际结果与终态范围

计划1–5已完成：新模块只收allowlist stimulus，拒绝expected/caseID；driver调用后才读独立v1期望；单current-purpose材料资格/noncurrent not_applicable与route/dispatch分轴。原v1字节与not_run历史不改，派生v2仍29/77、14proposed、52not_run。61variant仅partial_experimental的准入/路由facet匹配，16variant输入不足not_run；wholecase通过0。未知sourceKind预审已补真实RED后收紧支持域，另补source-specific规则与readOnly独立model授权缺口测试，未新增产品默认。

完整实验命令 `python3 -m unittest discover -s experiments/redesign/d01a-contract -p 'test_*.py' -v` exit0，33tests/0fail。初始空接缝RED exit1，20tests/24断言fail；driver RED exit1，26/5；未知来源RED exit1，21/3；source-rule/readOnly model RED exit1，23/3；变异编排RED exit1，1/1。最后谱系证明域RED exit1，26/3（未知继承Sensitivity、缺sourceversion、未知用途条款不能默认允许）。原始日志全在 `/workspace/reports/redesign-d01a-experiment-20261014/`，命令/exit/日志hash详见 [run-summary](../../experiments/redesign/d01a-contract/results/run-summary.json)。没有用import错误充RED。

`driver.py --derive-purpose-v2 --output experiments/redesign/d01a-contract/results/observations.json` exit0，61partial/16not_run/0局部比较差异；`driver.py --mutate-expected --output /workspace/reports/redesign-d01a-experiment-20261014/expected-negative.json` exit1/1差异，DUT actual保持不变。`mutation_runner.py --evidence-dir /workspace/reports/redesign-d01a-experiment-20261014/mutations --output experiments/redesign/d01a-contract/results/mutations.json` 检查器exit0，3子进程各exit1；各32测试，分别1/4/1断言fail。检出名：test_none_field_does_not_replace_actual_value_check、test_FullAllow_missing_Auto_rule_is_not_a_contract_block、test_none_target_does_not_downgrade_commercial_source。

16not_run为P01×2/D01×4/M02×2/C01–C04×5/N03×2/F11 replay×1，缺非supplier registry/transform/template/retention/newattempt/权威回执等接缝事实。实际classification/detector、真实source/modeissuer、Unicode/权限/消费/出站/效果/Android/SPIKE-01及M03仍未证。提交后发root与非作者redesign_m01_review固定SHA，不自行集成。

结构终验：16个授权新增路径，原v1全部文件逐字匹配1dc git对象，原跟踪文件diff为空；v2一一对应/当前purpose分轴/链接/日志及模块hash检查通过。SHA256SUMS首次误在根目录核相对条目报无法读取exit1，改在v2目录执行exit0/3项通过；此为结构命令工作目录修正，非runtime失败或产品CI。原始结构与hash日志外仓。
