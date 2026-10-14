# D01a / D03a 隔离实验 develop 集成终态

状态：用户明确授权后的正常合入与推送已完成；合后精确CI completed/success，无实验包集成阻断。

**现有 CI 不运行新 Python 实验。两路实验使用下述单独命令验证；Flutter/Doctor/Laya CI 是整体回归证据。实验合入不表示 M03 冻结，也不表示产品分类、授权、恢复或 Android 路径已实现。**

## 固定来源与正常集成

| 对象 | 完整 SHA |
| --- | --- |
| 原 develop / 首批基线 | `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d` |
| D01a 已审作者实验 | `ad548c35552fba74946827bc9cb5068d9ccc128d` |
| D03a 已审作者实验 | `eef7561289421c58e88896fa69c868403ca1d3c5` |
| 已审且CI成功候选 | `6a6664b1094c94c8db45f4ed274a170570c0cbb7` |
| 新 develop no-ff merge | `325e798d37044cbc0617f5bddbd14ccb9adec390` |
| 保持未改的 main | `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` |

B按本轮用户明确选择合入develop，不重复请求确认。fresh远端核对原develop仍1dc，候选是其后代；
增量严格33新增文件，仅两路experiments、I03派生purpose-v2、任务/非作者safe review/proof登记。
apps/packages、产品迁移、依赖、CI配置、原设计/合同/v1输入均无变化。两路非作者结论都是C0，仅实验范围；没有阻断该隔离包接收的设计条件。

在新独立integration工作区执行 `git merge --no-ff 6a6664b1094c94c8db45f4ed274a170570c0cbb7`，无冲突。
merge parents精确为1dc与6a；merge tree `37edd3f71eb6ddf3a2bc567c891eb189f9d7faf1`与已成功候选相同。
合后实验命令、范围和clean检查通过后，`git push origin HEAD:refs/heads/develop`正常成功；完整SHA读回325e，main仍cc7。
未强推、delete/deploy或修改作者分支，原工作区/活动writer保留。

## 合后单独实验命令

工作区 `/workspace/Muyon-integrate-contract-experiments-20261014`，实际HEAD为325e完整SHA：

```sh
python3 -B -m unittest discover -s experiments/redesign/d01a-contract -p 'test_*.py' -v
python3 -B -m unittest discover -s experiments/redesign/d03a-contract/tests -p 'test_*.py' -v
python3 -B experiments/redesign/d01a-contract/driver.py --output /workspace/reports/redesign-contract-experiments-20261014/postmerge/d01a-observations.json
python3 -B experiments/redesign/d03a-contract/run_experiment.py --output experiments/redesign/d03a-contract/leader-b-postmerge.json --evidence-dir /workspace/reports/redesign-contract-experiments-20261014/postmerge/d03a
```

两suite为33和24 tests，各exit0；两driver exit0。
D01a 61partial_experimental/16not_run/0局部差异，wholecase PASS 0；D03a 63partial/9not_run/274观察匹配/0差异，完整场景PASS 0。
临时reserved输出移到仓库外，git status为空，diff检查exit0；purpose-v2三项SHA校验exit0。
本次不重复旧专项；六语义逆变异与oracle独立性继续引用已审固定源的实际失败/恢复证据，merge tree未改这些源码。

原29 case/77变体、14 proposed_unfrozen规则、19组72场景及52主验收的not_run/partial历史保留；
原恢复actual/golden仍null。当前purpose资格不授dispatch/grant；host check是assumption，不是真实classifier。
SQLite实际故障只证明临时lab事务；策略常量/zero计数不证明真实业务执行或完整恢复。
前序报告`4b35d3305d64fd99182a8cd40892365c4f5f4365`与develop内任务书是此前未集成快照，保留不回写；本文件记录后续明确授权的实际集成。

## 两阶段CI

候选[CI38498073163](https://github.com/mightyoung/Muyon/actions/runs/38498073163)@6a completed/success，4199 pass/207 skip/0 fail。
合后[CI38500307094](https://github.com/mightyoung/Muyon/actions/runs/38500307094)精确head `325e798d37044cbc0617f5bddbd14ccb9adec390`，completed/success，job115645421285，2026-10-14T02:37:32Z完成。
实际4199 pass/207 skip/0 fail；analyze8/8、test8/8、Doctor23、Laya四脚本29tests、coverage均成功。
新snapshot source_sha/actions_run_id及八套exit/P/S/F与完整解码日志逐项一致。非作者与B独立核验，
日志SHA-256 `2d581f0e30c28b34eec1f82de6a91869b5f987c705a401874465d00499696e4a`。
[合后CI proof](redesign-experiments-20261014/postmerge-ci-proof.json)、[独立CI报告](redesign-experiments-20261014/postmerge-ci-independent-review.md)、
[B日志/快照互校](redesign-experiments-20261014/postmerge-root-ci-crosscheck.json)及[正常集成/实验proof](redesign-experiments-20261014/postmerge-integration-proof.json)分别保留。
不以候选CI代替合后CI，不将报告提交SHA当受测代码SHA。新Python实验未进入现有CI步骤，以上单独运行证据始终与CI计数分开。
原始日志只在仓库外 `/workspace/reports/redesign-contract-experiments-20261014/postmerge/`。

## SPIKE01最小环境与已有路径

只读追加报告见[最小环境盘点](redesign-experiments-20261014/spike01-minimum-environment-and-existing-paths.md)。
当前Python3.12.14可运行已有D01a/D03a stdlib实验；缓存Dart3.13.4及unorm缓存可支持既有固定Dart参考入口。
不重跑旧参考或声称Rust Unicode等价。已有Linux Flutter CI和手动Android包装workflow是配置路径；包装声明Java17/Flutter APK，
没有Rust/UniFFI/native-load/设备验证步骤。当前hosted runner工具缓存/设备实况未盘点，不能假定已齐备或擅自dispatch包装任务。

最小原生执行前置是已供给并准确记录的Rust/Cargo及依赖缓存，候选Android std targets，SDK platforms/build-tools与固定NDK Clang/LLD/sysroot，
含编译器的JDK和兼容离线Gradle/Kotlin插件缓存，同版UniFFI生成器/库/Kotlin绑定及JNA/AAR/native依赖，以及真实可用设备或runner加载机制。
候选ABI arm64-v8a/aarch64-linux-android、测试x86_64/x86_64-linux-android仍待实验核验；不冻结版本、API或设备矩阵。
4KB/16KB条件须覆盖所有原生依赖的对齐和实际加载，旧APK或仅主库静态检查不能替代。

当前workspace缺Rust/Cargo/targets、SDK/NDK/adb、javac/Gradle等实况；Java21只是runtime，缓存wrapper不证明Gradle distribution可用。
具体后续职责：Rust/UniFFI实验owner核crate/targets/依赖缓存，Android实验宿主owner核SDK/NDK/JDK/Gradle/JNA及实际load，
B核准确写范围/已有环境授权，非作者核同SHA及库hash/反例。以上只列需求，没有新派发native/product writer或安装步骤。

## M03停止线与writer暂停

M03保持blocked_contract：真实库加载、错误/回调/释放、两传输语义/摘要、跨端Unicode等价及唯一schema尚缺；
D01a真实分类/issuer/能力消费/出站和D03a真实正文/proof/receipt/IPC/业务执行仍缺。实验接收没有降低这些门槛。
B已向原D01a/D03a作者明确暂停依赖M03的产品写入，本执行器不放行Rust/Core/platform产品writer。
只读SPIKE盘点结束后也不恢复产品写入；下一步需要对应环境及真实证据闭合再独立决定。
未安装或下载新工具链、配置新凭据/安全权限/系统包、购买新资源、运行真实模型/Android/用户库或导出MUYON_EVAL_REAL。

本文件在独立review结果分支发布，属于325e之后的纯结果报告；[skip ci]不重复门禁，也不把报告提交当受测develop。
