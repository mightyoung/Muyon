# D01a admission/routing 实验接缝

本目录用Python stdlib执行内部实验材料准入和模式路由，非生产分类engine/DTO/schema。固定base为develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`，固定结果输入报告为 `8f8edf95983476a8963ea4cb35ee0a3b948aa862`；设计58fe、合同99c4d、根澄清和I03都保留原文。

实际结果：33个实验unittest通过；原29case的77variant中61个完成有限资格/路由对照，16个因输入不足not_run，已执行部分零比较差异；29个wholecase通过数0，52主case仍not_run。所有原classification-v1文件及原29/77的not_run历史未改。14规则仍proposed_unfrozen；M03仍blocked。

## 接缝与oracle分离

`seam.py`仅接收stimulus字典，既不读fixture文件，也不接收expected/case_id/variant_id。`fixture_adapter.py`以固定allowlist深拷贝八个已有输入区块，未从expected合成缺失信号。嵌套oracle/ID字段进入DUT时直接拒绝。DUT的源类型、字段、覆盖、signal、当前normalized/check/final引用、来源限制和模式事实逻辑独立于case身份。

`driver.py`先剥离oracle与ID，再调用DUT，随后比较层才访问独立v1期望。测试用Guarded字典断言expected访问发生于调用之后，改变caseID/variantID不改actual；expected-only负对照改期望而不改stimulus，DUT actual相同但比较失败。machine observations的actual是接缝函数输出，oracle单列仅当前purpose资格布尔值，不复制全部expected为actual。

I03已在实验表达层落实：只返回一个 `material={purpose,state,noncurrent:not_applicable}`，另有 `route`；无三套body布尔授权。`dispatch_performed`恒false。本机材料eligible既不是model/outbound许可，也不是grant、能力消费或已写入；Auto high/禁止/未冻、CAS及权限失败可以保持材料eligible而在route等待确认/拒绝/blocked_contract。

`classification-purpose-v2`只是原77条输入的表示派生：复制原stimulus区块，选原current-purpose oracle、其他purpose明确not_applicable。原始输入、wholecase/variant验收仍not_run，未来编码仍唯一归M03。派生过程独立于runtime结果，不能当作真实host issuer或新的产品DTO。

## 实际覆盖与准确限制

材料判断覆盖可信supplier.name声明与规范化后实际新值host-check事实的合取、known credential/疑似信号路由、来源继承与有效用途、未知field/source闭合、版本失效、当前用途规则/单元覆盖缺口与terminal状态。本机纯用户name只需该purpose必要规则，不等14广域分类；FullAllow不依赖Auto风险规则，实际ValueCheck缺失仍停止；Auto规则未冻blocked而非默认永久confirm。只读写/业务外发拒绝，model独立授权未提供则blocked_contract；不是只读一律禁止联网。scope/能力/身份/TLS/CAS/业务/账本硬前提不会被FullAllow绕过。

这些全部是对v1已经提供的 `host_check_assumption_not_classifier_result` 等合成事实的组合验证。没有扫描raw text/key、运行14实际分类规则、验证NFC/Unicode/源版本真实性、解析附件、取得真实权限/模式issuer、消费capability、序列化最终wire或派发/写库/查回执。`sensitivity_context`是当前假设的类别/继承路由，不是已完成实际可信分类；`attempt`是实验过程术语，不是新Sensitivity或正式DTO枚举。信号输入不能当凭据检测成功或零漏检证明。

16个not_run分支：P01两条非supplier字段注册路径；D01四条派生转换；M02两条模板注册；C01/C02/C03/C04共五条裁剪/留存/重放；N03两条新内容/新规则尝试；F11一条同intent权威回执重用。它们缺所需真实接缝证据，按输入特征决定not_run；不是从caseID或expected决定支持。其余61条最多partial_experimental，整案例还有实际分类、日志/出站、权限/CAS/消费与效果等未跑facet。

## 可复跑命令

从worktree根运行：

```sh
python3 -m unittest discover -s experiments/redesign/d01a-contract -p 'test_*.py' -v
python3 experiments/redesign/d01a-contract/driver.py --output /tmp/d01a-observations.json
python3 experiments/redesign/d01a-contract/driver.py --mutate-expected --output /tmp/d01a-expected-negative.json
python3 experiments/redesign/d01a-contract/mutation_runner.py --evidence-dir /tmp/d01a-mutants --output /tmp/d01a-mutations.json
```

正常suite/矩阵/变异检查器exit0；expected-only负对照应exit1（1比较差异）。变异检查器在仓库外临时复制接缝和测试，不改正常源码/fixture；三mutant子进程各exit1，由断言而非import/语法失败检出。变异子套件32测试，不含递归变异检查测试；正常完整实验套件33测试。为保持原始日志在仓库外，`--evidence-dir`拒绝仓库内路径。独立复跑默认不要加 `--derive-purpose-v2`，该开关仅生成授权派生目录。

## TDD及逆变异证据

原始日志位于仓库外 `/workspace/reports/redesign-d01a-experiment-20261014/`：初始RED 20测试/24断言失败（空接缝）；driver RED 26测试/5失败；未知source域RED 21测试/3失败；source-specific规则/readOnly model RED 23测试/3失败；变异编排RED 1测试/1失败。均为缺行为的断言，不把导入错误当RED。谱系证明域RED 26测试/3失败（未知继承类别、缺source version、未知用途条款）；随后完整GREEN 33测试/0失败。

| 逆变异 | 子进程exit | 断言失败数 | 必需检出名 |
| --- | ---: | ---: | --- |
| bypass_actual_value_check | 1 | 1 | test_none_field_does_not_replace_actual_value_check |
| require_Auto_rule_in_FullAllow | 1 | 4 | test_FullAllow_missing_Auto_rule_is_not_a_contract_block |
| downgrade_commercial_lineage | 1 | 1 | test_none_target_does_not_downgrade_commercial_source |

[非秘密结果](results/observations.json)、[变异摘要](results/mutations.json)与[命令/来源摘要](results/run-summary.json)仅为实验接缝证据；raw logs未提交。它们不证明产品CI、29wholecase/52主验收、D01b、M03或SPIKE-01通过。

实施计划及独占范围见 [任务书](../../../docs/tasks/REDESIGN-D01A-EXPERIMENT-20261014.md)。仍须精确SHA非作者复审、真实检测器与覆盖/误报漏报证据、权限/账本/出站/回执、跨端Unicode和实际Androidload/恢复证据。未安装/新依赖/网络/真实库/设备/模型/MUYON_EVAL_REAL，未push/merge/main/deploy。
