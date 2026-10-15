# OC13 / OC14 / CR10F3：0ab 最新组合独立复验

本任务只独立复验，不合入 develop/main。受测代码基线为 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`，报告分支 `review/oc-triple-0ab-independent-20261015`。报告提交与受测代码提交分别标明。

## 来源与组合

2026-10-15 再次读取远端，三个作者分支精确保持 OC13 `c3fe22b5769016fc6e686f290213a52941dadb3f`、OC14 `4b68b09be94463e19912e2469036e7435b3d4104`、CR10F3 `9f5216bb3768deb84522fb6c91415442f9ad6268`。当前 develop 为上述 0ab；main 为 `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`。

沿用已纠正的集成事实：指定源提交本身不属于 develop 祖先，不能声称原 SHA 已直接合入。实际等价集成提交分别为 `ef8803c974217de169a74ebe2506c87452684edb`、`19e59a94b64aa1b3f52dbf61748640c93513babe`、`cd3bb02d95f99c9f97c35d431c2c4976b6c3a52c`。前两项单提交 stable patch-id 相同；CR10F3 比较 `ff8156d..9f5216bb` 的累计 apps/packages 补丁，stable patch-id `9505b1ae3031a102f4083f198109c6bac2b95cf8` 与集成提交相同。11 个交付路径中 10 个 blob 与源相同，adapter 后续只读回执扩展为已审差异。

本次 a01→0ab 的 `apps/`、`packages/`、`scripts/`、`pubspec.yaml`、`pubspec.lock` 与原全量 CI workflow 无差异；非作者核实同时直接比较较新目标实跑基线 `3836149416020a0ac58f9e7ca788c20e66688e0e`→0ab，上述各路径也均零差异，目标测试和变异触及的产品与测试代码保持不变。无需再摘取重复补丁。

## 目标与逆变异证据

以下为既有独立实跑，受测 SHA `3836149416020a0ac58f9e7ca788c20e66688e0e`；本次重新核实其日志、恢复证明及代码等价，不冒称重新运行。

| 验证 | 结果 | 关键行为 |
| --- | --- | --- |
| 五个目标文件，初始与恢复后 | 各 39 pass / 0 skip / 0 fail | OC13、OC14、宿主探针及 hosted 权限回归 |
| OC13 catch 返回 false | 2 pass / 2 fail | 两新增测试均 Expected true / Actual false |
| OC14 allowClear=false | 6 pass / 1 fail | explicit null 清空失败，Expected succeeded / Actual failed |
| CR10F3 facts 恒 false | 6 pass / 3 failure / 1 widget error | error 事件 hidden:false；tainted、unknown、转发及关联 widget 诊断，不称四个独立安全边界 |
| CR10F3 catch 返回 false | 9 pass / 1 fail | 读失败应 unknown：Expected null / Actual false |

四轮临时逆变异均恢复原字节；恢复后产品 diff 为空，strict muyon_ui analyze exit 0。本次复查的较新原始日志、恢复证明及 `latest-0ab-static-proof.json` 留在仓库外 `/tmp/oc-triple-current-20261015`；较早一轮证据和 a01 核对也原样保留。非作者简明复核：`/tmp/oc-triple-current-review-20261015.md`。

## 最新完整 CI

[完整 CI 38740489239](https://github.com/mightyoung/Muyon/actions/runs/38740489239) 的 API head 与日志 checkout 均精确为 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`，completed/success，终态 `2026-10-15T13:31:44Z`。八个 analyze 与八个套件成功；module_api 276、muyon_ui 392P/152S、prototype 39P/1S、research 365P、supplier_core 498P/4S、host 2312P/3S、ui_preview 15P、inquiry 302P/47S，总计 4199 pass / 207 skip / 0 fail。Doctor 23、Laya 29 与 coverage 步骤成功。skip 不作真机或真实模型验收。

完整普通日志 SHA256 `8c7bb8a372d83c660912e921a52c8962e4476969913a366573b4bf7cac13830b`，日志与结构化观察位于仓库外 `/tmp/rd-android-rust-bridge-20261015`。这是已经执行的当前组合 CI，本次只重新核实其终态，没有重复触发。

[CR10F3 源 CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069) 为指定完整源 SHA 的 success；源 module_api 198 和旧组合 250 均不能代替当前组合 276。

## 结论与边界

三项有界交付无新增阻断；等价交付已在当前组合中，无需重复合入。这不是整体 develop 发布批准。

- OC13 两测试及 catch=false 必失败要求成立。
- OC14 省略保留、null/空串清空、0 保存、[] 替换、空 values 拒绝均有特征断言。false 在公开 schema 提前拒绝，不能写成经过 normalizer 或保存成功；测试注释与精化 invalid_parameters 属非阻断建议。
- CR10F3 生产 activate 仍未传 task/conversation，缺身份进入 unknown 并强制确认；这是安全退路，完整生产身份接线仍待后续实现和验收。作者 RED 12 fail 含清理超时连锁，不作十二项独立行为证据。
- 已知宿主 2380 断言基线问题不在本任务重复修改；本次以当前完整 CI 实际终态判断。

仅提交审查摘要，不改产品和作者分支，不提交原始日志。未 merge develop/main、forcepush、delete、deploy、运行真实模型或 Android，也未导出 MUYON_EVAL_REAL；各活动 writer 保留。
