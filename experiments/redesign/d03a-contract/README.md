# D03a 可执行合成合同实验：实施计划

状态：独立实验已执行，可固定SHA review；完整72场景闭合PASS为0，M03仍blocked_contract。固定输入为recovery fixture `55480f06490983a54e38908b043b06b4b02df451`，19groups/72scenarios；原v1历史not_run/actual/golden不改。基线develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`，登记报告 `8f8edf95983476a8963ea4cb35ee0a3b948aa862`。

Goal：用实际独立输入驱动的实验接缝，验证可执行的恢复语义和真实临时SQLite持久边界，逐场景明确运行层级/缺口。

Architecture：`seam.py`只接收input facts/stimuli，在独立lab表维护投影/水位、输入身份和效果。`run_experiment.py` thin driver在调用DUT前只传input，无expected/caseID；DUT返回observations与unsupported/gaps后，driver才与固定expected比较。实际回执/摘要不足或M03未冻结者不从expected推造事实。SQLite只为临时合成事务实验，无产品source/迁移/协议DTO。

Tech stack：Python3 stdlib unittest/sqlite3/subprocess/tempfile；不安装依赖。Spec：40f3合同及55480 fixture。

## 实施顺序与依赖

- [x] 先写独立行为tests：错域大seq、缺口/重复、快照覆盖/迟到、旧epoch显示隔离与独立ledger查询、未知零重发/可信新指令、PendingInput留存、hard prerequisite与FullAllow风险分轴。
- [x] 运行实验完整 unittest suite，记录真实AssertionError RED（不以import错误作为RED）。
- [x] 最小actual reducer + SQLite boundary commit/read；接收/应用/持久状态分离，未支持动作返回具体gap，不能expected回显。
- [x] 额外独立物理故障tests：子进程在投影写后cursor写前与commit后通知前退出；重开真实lab SQLite验证旧完整边界或新完整边界。
- [x] thin adapter从git读固定72输入，调用前剥expected/ID/refs，调用后仅comparison读取oracle；报告matched/unavailable/mismatch及pass/partial/not_run，明确实验层级。
- [x] 全部实验suite GREEN后，至少两项必要逆变异真实失败：移除完整域拒绝；旧epoch吞掉已验证回执；以及原子边界变异。变异日志外仓，恢复原代码再GREEN。
- [x] 固定source/fixture/实现hash、安全machine报告/commands/exits/范围检查；本地commit，送root与独立reviewer，不push/merge。

## Review focus

输入不含payload/receipt/可信proof时不能生成成功/身份；同域seq只许可投影，不原audit；旧epoch仅display fence；SQLite证明只限该lab事务；纯FullAllow风险不能吞真硬限制。schema/摘要/proof/跨端/真实历史布局不足标M03停止条件，不自行冻结。

原始日志只外仓 `/workspace/reports/d03a-contract-experiment-20261014/`。无真实用户body/credentials/database/native/model/network/MUYON_EVAL_REAL。52主case和29分类子case不因此通过。

## 最终运行证据与分层结果

从仓库根目录运行，仅实验自己的完整suite：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s experiments/redesign/d03a-contract/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 experiments/redesign/d03a-contract/run_experiment.py --evidence-dir /workspace/reports/d03a-contract-experiment-20261014
PYTHONDONTWRITEBYTECODE=1 python3 experiments/redesign/d03a-contract/mutations.py --evidence-dir /workspace/reports/d03a-contract-experiment-20261014
```

完整实验suite **24 tests，exit0**：22行为/adapter tests与2物理SQLite故障tests。原始初始RED为17 tests/16 AssertionError failures（exit1）；adapter信息流另2 tests先RED失败；许可投影/修复另3 tests先RED失败；volatile11/durable10与existing checkpoint初始化先取得1/2项真实RED后修复。所有测试只对实验实现，不是产品/旧Flutter suite或52主case。

固定原72场景：[observations.json](observations.json) **63 partial、9 not_run、0完整场景PASS**，274 assertion matches、0 mismatch。匹配包含策略输出、初始zero/False以及symbolic lab数据；不自动等同实际操作执行证据。每case记录action mechanism、observation provenance、具体gap/不可比较项，DUT不接expected/ID。原fixture字节、72 not_run、actual/golden=null保持；另加的24 tests不算进原72。

[mutation-observations.json](mutation-observations.json)记录3个必要逆变异，全部AssertionError **exit1**，字节恢复后完整24-test suite **exit0**：

1. 去除完整domain拒绝：即使seq相邻，错store/scope/stream也推进；`test_domain_rejects_larger_seq_from_each_wrong_identity`真实失败。
2. 仅因old epoch抹掉effect hint：当前独立lab查证结果失去关联；`test_old_epoch_display_rejected_but_ledger_lookup_preserves_effect`真实失败。
3. state写后、cursor写前提前commit：子进程在中间exit77，重开见new state/old cursor混版；`test_process_exit_between_state_and_cursor_rolls_back`真实失败。

变异只改保留区seam源，finally原字节恢复；source hash在mutation报告与场景报告核对。所有原始日志外仓，[verification-evidence.json](verification-evidence.json)列命令、exit、日志hash和当前实现hash。初跑33/34 pass是过宽的实验分类，保留外仓历史日志；已按在途审查降级，固定报告无完整scenario PASS。

## 初始化与实际持久证明范围

`reduce`首先读既有committed lab SQLite checkpoint，存在时不由volatile active覆盖；新lab仅用合成durable输入seed。active11/durable10恢复从10，event12进入缺口暂停，不跳过11。existing lab checkpoint11即使active50，也从已提交11接event12。初始durable错域或existing checkpoint域不同会停止并给M03 bootstrap gap；不能用大seq混域。

SQLite实验用独立`boundary`/`lab_facts`表。实际atomic_boundary在同一事务写state与cursor；两物理tests真实子进程`os._exit(77)`后重开SQLite，分别核对old完整pair/new完整pair。这只证明该lab事务算法。固定72中的`inject_process_death`动作仍unsupported，不能借额外物理test宣称这七fixture fault已按实际产品输入执行。

## 明确缺口和停止条件

- Event payload、实体投影正文/实际digest不在原metadata输入中：只能symbolic timeline与cursor guard，不证明产品projection内容应用。
- snapshot完整性、权限与advance proof是合成注入label，不含实际parser/signature/schema/proof verifier；M03单源未冻结，stream重建/真实bootstrap未实现。
- 旧epoch回执分流只接受注入的lab lookup response并写/读独立lab事实；缺actual receipt ID/digest/来源验证。它不是Rust权威EffectReceipt或真实provider查询。
- compression/snapshot/draft变换未实现。PendingInput仅最小metadata身份保存/新连接读取；`process_exit_then_restart`不是实际进程重启，body不物化，不能证明正文恢复；duplicate IPC零计数没有真实消息写/去重实现。
- unknown/new-intent/hard-limit/FullAllow部分仅输入驱动政策决策。aggregate硬前提bool不替代逐项scope/权限/用途/capability/CAS检查；trusted user关联没有生产签名。没有business executor或外发dispatch可供声称成功/zero-write证明。
- supplier实际受控提交、幂等/回执、同规范名new intent revision+1、正式备份账本保全仍unsupported/not_run；保留各case具体M03停止条件，不从expected补参数。

所有产品runtime为not_run，M03 blocked，Rust frozen schema/桥/IPC/native未验证。body、receipt、proof、true endpoint/能力不足均继续阻断对应入口；不能将FullAllow纯风险变成额外确认来掩盖这些硬前提缺口。
