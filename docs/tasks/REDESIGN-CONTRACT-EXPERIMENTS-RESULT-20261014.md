# v1.3.2 D01a / D03a 第二批实验结果

状态：两路固定实验已获非作者C0；组合轻量验证通过，精确候选CI completed/success。
本批只交付隔离实验和报告，未合入develop/main。没有冻结M03或生产schema。

## 固定身份与前置

| 对象 | 完整SHA / 引用 |
| --- | --- |
| 首批终态 | `8f8edf95983476a8963ea4cb35ee0a3b948aa862` |
| develop基线 | `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d` |
| D01a作者固定实验 | `ad548c35552fba74946827bc9cb5068d9ccc128d`，review/leader-b-d01a-experiment-source-20261014 |
| D03a作者固定实验 | `eef7561289421c58e88896fa69c868403ca1d3c5`，review/leader-b-d03a-experiment-source-20261014 |
| 组合候选 | `6a6664b1094c94c8db45f4ed274a170570c0cbb7`，task/leader-b-contract-experiments-20261014 |

三个新引用均正常atomic push后完整SHA读回；作者原分支/worktree和其它writer保留。
develop/main保持原值，main为`cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`。
依赖M02→D01a/D03a/SPIKE01隔离验证→M03允许实验先行，生产Rust/Core/platform仍阻断。
本批无apps/packages、产品迁移、依赖、CI配置、原合同、原设计或v1输入修改。

## 实际轻量验证与独立审查

组合工作区`/workspace/Muyon-leader-b-contract-experiments-20261014`实际执行：

```sh
python3 -m unittest discover -s experiments/redesign/d01a-contract -p 'test_*.py' -v
python3 -m unittest discover -s experiments/redesign/d03a-contract/tests -p 'test_*.py' -v
python3 experiments/redesign/d01a-contract/driver.py --output /workspace/reports/redesign-contract-experiments-20261014/d01a-normal.json
python3 experiments/redesign/d01a-contract/driver.py --mutate-expected --output /workspace/reports/redesign-contract-experiments-20261014/d01a-expected-negative.json
python3 experiments/redesign/d03a-contract/run_experiment.py --output experiments/redesign/d03a-contract/leader-b-recheck.json --evidence-dir /workspace/reports/redesign-contract-experiments-20261014/d03a
python3 experiments/redesign/d01a-contract/mutation_runner.py --evidence-dir /workspace/reports/redesign-contract-experiments-20261014/d01a-mutations --output /workspace/reports/redesign-contract-experiments-20261014/d01a-mutations.json
python3 -B experiments/redesign/d03a-contract/mutations.py --evidence-dir /workspace/reports/redesign-contract-experiments-20261014/d03a-mutations
```

两完整suite为33及24 tests，各exit0。正常两driver exit0；D01a故意错误expected负控exit1，差异1，77actual保持不变。
两变异检查器exit0表示分别检出三项实际失败，六子进程均exit1；恢复后源码一致/工作区干净。
D03a临时reserved输出已移至仓库外，未提交。日志只外仓，diff检查exit0；purpose-v2三项SHA校验exit0。

| 路线 | 固定输入结果 | 非作者结论 |
| --- | --- | --- |
| D01a | 29case/77variant：61partial_experimental、16not_run、0局部差异、0wholecase PASS | C0，仅准入/模式决策实验 |
| D03a | 19组/72场景：63partial、9not_run、274观察匹配、0差异、0完整场景PASS | C0，仅恢复策略/SQLite实验接入 |

D01a实现I03单current-purpose材料资格，noncurrent not_applicable；资格、route、dispatch分轴。
可信字段声明不能代替实际当前新值覆盖；已闭合未知sourceKind、来源版本/继承类别/用途条款缺失、来源特定规则与readOnly model授权缺口的实验负例。
三逆变异分别绕过actual值检查、令FullAllow依赖Auto规则、降商业来源类别，均被指定断言检出。
host输入仍是assumption，未实现真实credential扫描、14生产规则或真实能力issuer/消费。

D03a使用临时合成SQLite事务，24tests包括两次真实子进程os._exit77并重开数据库。
三个逆变异覆盖完整cursor域、旧epoch吞effect hint、state/cursor之间提前commit。
在途审查纠正过宽PASS及active/durable初始化：从已提交边界恢复，active11/durable10不会跳过11，
现存checkpoint不会被volatile初态覆盖。额外实际故障tests不算原72场景，零计数/策略常量只记录其来源和缺口。

非作者对全部77/72行改变oracle及case身份，actual均不变；错误oracle只在调用后comparison报差异。
原v1字节和not_run历史保留；恢复actual/golden仍null，29wholecase及52主验收未升级。
详见[组合轻量proof](redesign-experiments-20261014/combination-preci-proof.json)、
[D01a审查](redesign-experiments-20261014/d01a-independent-review.md)和[D03a审查](redesign-experiments-20261014/d03a-independent-review.md)。

## 精确CI

[CI38498073163](https://github.com/mightyoung/Muyon/actions/runs/38498073163)受测完整SHA为
`6a6664b1094c94c8db45f4ed274a170570c0cbb7`；completed/success，job115638313638，2026-10-14 02:10:19 UTC完成。
8/8 analyze、8/8 test、Doctor23、Laya四脚本8/4/8/9及coverage均成功；实际4199 pass / 207 skip / 0 fail。
完整解码日志SHA-256 `b4f6668827c1b399970580d0ca7f9753d1e65788405467536a61abbae83e1720`、checkout全SHA、
新snapshot的source_sha/actions_run_id/八套件exit与P/S/F逐项匹配，B再次独立核验。
CI结束后B在固定6a工作区以 `python3 -B -m unittest discover` 对以上两路再次取得33/24 tests exit0，工作区干净。
详见[CI终态proof](redesign-experiments-20261014/ci-terminal-proof.json)及[独立CI报告](redesign-experiments-20261014/ci-terminal-review.md)。
既有CI不包含新Python实验，
其整体Flutter/Doctor/Laya回归证据与上述57新实验tests分开记录。此结果报告提交不冒称受测SHA。

## SPIKE01与继续停止条件

SPIKE01只读盘点已完成：仅找到Java21运行时和缓存Flutter/Dart/wrapper；未找到Android SDK/adb/NDK、
JDK compiler、Gradle/Kotlin CLI、Rust/Cargo/Android targets或已证实UniFFI/JNA依赖。
设备状态unknown/not_queryable，未启动服务、模拟器或安装设备。标准路径/PATH盘点不排除未注册路径，
既有runner配置/Flutter APK不证明真实Rust库加载。安全命令/exit/版本证据及报告hash见[intake-state](redesign-experiments-20261014/intake-state.json)，
原文在`/workspace/reports/spike01-readonly-20261014/`。

M03保持blocked_contract：真实Android加载/错误/回调/释放、两传输语义与摘要、跨端Unicode等价及唯一schema未齐。
D01a仍缺真实分类/检测/来源及权限权威、能力消费/序列化/派发；D03a仍缺真实projection body/digest、snapshot/parser/proof、
权威receipt、正文恢复/IPC去重/业务提交/幂等回执和产品故障动作。
这些条件不从expected补造，不能将FullAllow纯风险误作硬阻断来掩盖缺失硬前提。
可采纳范围只限这批实验接缝、派生purpose表示和明确分层报告，不能宣称产品模式/恢复验收完成。
未安装或下载工具、未建凭据/购买资源、未真实模型/Android/用户库、未导出MUYON_EVAL_REAL，未forcepush/delete/deploy。
