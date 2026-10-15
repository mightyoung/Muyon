# OC13 / OC14 / CR10F3 最新组合独立复验

本任务只复验，不合入 develop/main。代码基线为 `a01dcc83348c705fb8c6e3905aa9df8999058b1a`，审查分支 `review/oc-triple-a01-independent-20261015`。

## 固定来源与证据更正

远端三个作者分支仍精确指向：OC13 `c3fe22b5769016fc6e686f290213a52941dadb3f`；OC14 `4b68b09be94463e19912e2469036e7435b3d4104`；CR10F3 `9f5216bb3768deb84522fb6c91415442f9ad6268`。

此前 `OC13-OC14-CR10F3-independent-reverify-20261015.md` 写三个源提交均为基线祖先，该说法不正确。本次逐个 `merge-base --is-ancestor` 均为 exit 1；应以集成提交、补丁和文件内容核对为依据。旧报告的测试原始终态不因此改写。

非作者独立核实：实际集成祖先为 OC13 `ef8803c974217de169a74ebe2506c87452684edb`、OC14 `19e59a94b64aa1b3f52dbf61748640c93513babe`、CR10F3 `cd3bb02d95f99c9f97c35d431c2c4976b6c3a52c`。前两项单提交 stable patch-id 与指定来源相同；CR10F3 必须比较作者 `ff8156d..9f5216bb` 的累计 apps/packages 补丁（含前置测试提交），其 stable patch-id `9505b1ae3031a102f4083f198109c6bac2b95cf8` 与 cd3bb02 相同，不能宣称最后单提交本身等价。11 个交付路径中 10 个 blob 与源相同，adapter 后续只读回执扩展是已审明的差异。

## 目标测试与逆变异

已有独立实跑受测 SHA `3b4a7b27afded3f2d3007028d793aa06bd564312`；新旧基线的 `apps/`、`packages/`、`scripts/`、`pubspec.yaml`、`pubspec.lock` 和原全量 CI workflow 无差异。本次不冒称重新运行了下列目标测试，采用原实跑证据、代码等价核对和最新完整 CI 共同判断。

- 五目标文件：39 pass / 0 skip / 0 fail；全部恢复后再次 39/0/0。
- OC13 catch 返回 false：2 pass / 2 fail，两个新增测试均失败。
- OC14 禁用 allowClear：6 pass / 1 fail，显式 null 清空失败。
- CR10F3 facts 恒 false：6 pass / 4 fail，包含关联 widget 诊断，不称四个独立安全边界。
- CR10F3 catch 返回 false：9 pass / 1 fail，Expected null / Actual false。
- 四轮临时变异均恢复原字节；muyon_ui strict analyze exit 0。

原始日志仅在仓库外 `/tmp/oc-triple-independent-20261015`；新鲜 CI 日志与独立核对在 `/tmp/oc-triple-a01-independent-20261015`。原始日志不入仓库。

## 最新完整 CI

[38727405280](https://github.com/mightyoung/Muyon/actions/runs/38727405280) 的 API head 与日志 checkout 均为上述完整 a01 SHA，completed/success，2026-10-15T11:49:33Z 终态。8 个 analyze 和 8 个套件成功：module_api 276；muyon_ui 392P/152S；prototype 39P/1S；research 365P；supplier_core 498P/4S；host 2312P/3S；ui_preview 15P；inquiry 302P/47S。总计 4199 pass / 207 skip / 0 fail；Doctor 23、Laya、coverage 成功。skip 不作为平台或真实模型验收。

[CR10F3 source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069) 也重新核对 exact `9f5216bb3768deb84522fb6c91415442f9ad6268`、completed/success。源 module_api 198 和旧组合 250 不代替最新 276。

## 判断边界

结论：三项有界交付无新增阻断，已有等价交付无需再次摘取或合入。该结论不构成整体 develop 发布批准；完整生产身份接线若列为后续验收条件，仍须实现并另验。

OC13 两测试和 catch false 失败要求成立。OC14 锁定省略保留、null/空串清空、0 保存、false 在公开 schema 提前拒绝、[] 替换、空 values 拒绝；不声称 false 经过 normalizer 或保存成功。测试注释可澄清该提前拒绝，负例可细化 invalid_parameters，属于非阻断建议。

CR10F3 生产 activate 仍未传 task/conversation；缺身份进入 unknown，强制确认是安全退路，完整生产身份接线仍待后续。作者 RED12fail 含清理超时连锁，不作为十二项独立行为证据。已知宿主 2380 断言问题不在本任务重复修改。

未改产品或作者分支，未真实模型/Android，未导出 MUYON_EVAL_REAL，未 merge develop/main、forcepush、delete 或 deploy。各活动 writer 保留。报告提交 SHA 与受测代码 SHA 分别标明。
