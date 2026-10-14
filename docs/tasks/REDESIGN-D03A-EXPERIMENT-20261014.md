# REDESIGN D03a 独立恢复合同实验

状态：**实验实现与suite已运行，可固定SHA非作者审查；原72完整scenario PASS为0，M03 blocked_contract**。单writer `/root/redesign_d03a_contract`，独立branch `task/leader-b-d03a-contract-experiment-20261014`，worktree `/workspace/Muyon-leader-b-d03a-experiment-20261014`，起点 `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`；登记报告 `8f8edf95983476a8963ea4cb35ee0a3b948aa862`。

仅 `experiments/redesign/d03a-contract/` 和本文，未改原v1、合同、product、design、M03schema、CIconfig或root共享文件。计划先写在 [README](../../experiments/redesign/d03a-contract/README.md)，按此前正式委派继续执行。输入固定 `55480f06490983a54e38908b043b06b4b02df451`；原19组72scenarios not_run/actualnull/goldennull字节保持。

## 实际实现与证据

独立Python stdlib reducer/SQLite lab store、薄adapter、完整实验tests、逆变异工具与安全machine报告。DUT仅接deep-copy input facts/stimuli，不接expected、case ID、refs；actual计算后adapter才读取固定oracle comparison。没有第二产品DTO/源算法或RustFrozen Core。

实际完整实验suite **24 tests exit0**（22行为/adapter＋2真实SQLite子进程故障）；TDD初始17 tests有16 AssertionError失败exit1，另adapter/projection/持久初始化增量分别先RED再GREEN。latest原72 driver **63 partial/9 not_run/0完整PASS，274 matched/0 mismatch，exit0**；matches也包含政策值/初始化默认，不称实际业务操作证明。

必要逆变异 **3项各exit1 AssertionError**：完整domain拒绝移除、旧epoch吞真实关联hint、state/cursor之间提前commit导致物理混版。恢复后完整24 tests exit0且source byte hash相等。准确命令在README，原始logs仅 `/workspace/reports/d03a-contract-experiment-20261014/`；[verification-evidence](../../experiments/redesign/d03a-contract/verification-evidence.json)与[mutation-observations](../../experiments/redesign/d03a-contract/mutation-observations.json)记录安全hash、退出码与变异target。

## 重要边界修正与未满足项

在途root/reviewer指出旧分类过宽；已明确每action mechanism及每observation来源，compression仅赋值不称变换、duplicateIPC无实际message去重、aggregatebool不称hard事实核验、连接重开不称进程恢复。原33/34 pass初跑只留外仓历史，固定报告全部partial/not_run。

volatile active11/durable10风险先真实RED后窄修：恢复以已提交lab boundary为准，event12不能跳过11；existing checkpoint不被输入active50覆盖。额外独立负例不算原72。真正durable atomic证明仅限两独立物理子进程SQLite tests；原72故障动作没有完整产品内容，仍partial/unsupported。

缺真实projection payload/body、snapshot parser/proof、receipt ID/digest验证、用户关联签名、逐项授权/CAS及business executor。仅policy/symbolic lab行为不闭合整scenario，不补expected参数，不生成产品成功/零写证据。supplier新intent同名revision、幂等/真实receipt、正式备份等尚未实现；逐case M03停止条件在 [observations](../../experiments/redesign/d03a-contract/observations.json)。

52主case与29分类子case仍not_run，Rust/桥/IPC/native未验证。没有真实用户数据/credential/model/device/network、安装/newdeps/付款/Native LE04实验或MUYON_EVAL_REAL。仅本地正常commit；rootB唯一集成人，writer不push/merge/main/force/delete/deploy。固定SHA后送root及oc_triple_runtime_verify审查，未预宣C0。
