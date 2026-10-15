# OC13 / OC14 / CR10F3 当前 develop 独立复验

结论：在 develop `3836149416020a0ac58f9e7ca788c20e66688e0e` 上，三项有界交付通过当前目标测试、必要逆变异及精确组合 CI 核验，无新增阻断。代码已在 develop 中，无需再次摘取。本次仅独立复验，不执行合入。

## 来源与身份

| 交付 | 未变更的远端固定源 SHA | develop 中对应提交 |
| --- | --- | --- |
| OC13 | `c3fe22b5769016fc6e686f290213a52941dadb3f` | `ef8803c974217de169a74ebe2506c87452684edb` |
| OC14 | `4b68b09be94463e19912e2469036e7435b3d4104` | `19e59a94b64aa1b3f52dbf61748640c93513babe` |
| CR10F3 | `9f5216bb3768deb84522fb6c91415442f9ad6268` | `cd3bb02d95f99c9f97c35d431c2c4976b6c3a52c` |

更正旧复验文档的来源表述：三个原始源提交均不是当前 HEAD 的 Git 祖先；上表对应整合提交才是祖先。OC13、OC14 的 stable patch-id 分别与原始源一致。CR10F3 的测试先行与实现被组合折入一个提交，patch-id 因父树差异而不同，但整合提交的九个交付文件 blob 与固定源逐一完全一致。当前 11 个交付文件有 10 个仍与固定源逐字一致；唯一 adapter 差异为后续只读 BusinessReceiptLookup 能力。当前 apps/packages 与上轮已测 `3b4a7b27afded3f2d3007028d793aa06bd564312` 无 diff。

已依任务书、REVIEW、不变量审计、相关设计与 ADR，由非作者核实代理执行代码检查及运行验证。未发现适用 AGENTS.md；工作区 .agents/.codex 为空。隔离分支 `review/oc-triple-current-20261015`；工作区 `/tmp/Muyon-oc-triple-current-20261015`。

## 新鲜运行证据

Flutter 3.47.5 / Dart 3.13.4，Linux；离线 pub get 成功，依赖缓存复用不作为测试证据。五个目标文件（dynamic_external_content_default、oc14_update_value_semantics、inquiry_host_taint_probe、inquiry_module/host_taint_probe、assistant_permission_hosted）首次与恢复后均 exit 0，**39 pass / 0 skip / 0 fail**，均有 JSON done success 终态。

| 临时单点逆变异 | 本轮实跑结果 |
| --- | --- |
| OC13 getter catch true → false | exit 1；2P/2F；两个新测试均 Expected true / Actual false。 |
| OC14 allowClear true → false | exit 1；6P/1F；显式 null 清空例 Expected succeeded / Actual failed。 |
| CR10F3 facts.requiresConfirmation → false | exit 1；6P，3 个直接断言失败及 1 个 widget error；不作四个独立行为证据。 |
| CR10F3 probe catch null → false | exit 1；9P/1F；读取失败例 Expected null / Actual false。 |

四轮 finally 均恢复原字节；恢复后工作树干净。严格 muyon_ui analyze exit 0，No issues found（7.2s）；另补跑 muyon_ui 全包，exit 0、392 pass / 152 skip / 0 fail，done success。最终报告提交只新增本摘要，产品代码无改动，原始日志不入仓库。

## 组合 CI 终态

重新获取 [完整 CI 38680501818](https://github.com/mightyoung/Muyon/actions/runs/38680501818) 的 run、jobs、完整 decoded 日志和 coverage suite outcomes。head、checkout、coverage source_sha 均精确为 `3836149416020a0ac58f9e7ca788c20e66688e0e`，首次 attempt completed/success，job `116243708768` 于 2026-10-15T04:33:48Z 完成，8 套测试总计 **4199 pass / 207 skip / 0 fail**。八套分别为 module_api 276P；muyon_ui 392P/152S；prototype 39P/1S；research 365P；supplier_core 498P/4S；host 2312P/3S；ui_preview 15P；inquiry 302P/47S。Analyze/test、Laya、coverage 步骤均 success。

同一精确 SHA 的 [Core CI 38680501844](https://github.com/mightyoung/Muyon/actions/runs/38680501844) 首次 attempt completed/success。[CR10F3 source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069) 重新核对为 exact `9f5216bb3768deb84522fb6c91415442f9ad6268`、首次 attempt completed/success。源 module_api 198、旧组合 250 不替代当前 276 的组合证据。现存 CI 已精确覆盖当前代码，故不重复触发相同代码 CI；纯报告提交使用 skip ci，报告提交 SHA 不冒称受测代码 SHA。

## 条件与限制

- OC13 满足两个独立探针测试及 catch false 必须失败要求。
- OC14 锁定省略保留、null/空串清空、0 保存、false 在公开 schema 层拒绝、[] 替换、空 values 拒绝。false 不是 boolean normalizer 保存证据；符合任务失败照实记录且不改源码的停止条件。已有注释澄清和错误码细化建议仍非阻断。
- CR10F3 覆盖宿主探针及缺失/unknown/身份不匹配/抛错强制确认，hosted bypass → confirmWrites 保留。生产 activate 仍未传 task/conversation，unknown 强制确认是安全退路；不称完整生产身份接线或非宿主污染继承。
- 作者 RED12fail 含清理超时连锁，不当作十二个独立行为证据。宿主 2380 断言为已知其他任务处理基线，本轮未重复改动。
- 未运行真实模型/Android，未导出 MUYON_EVAL_REAL；未 merge develop/main、forcepush、删除或部署。所有作者分支及活动 writer 保留。远端首末核对固定源和 develop/main 未改变。

原始证据和非作者报告仅存仓库外 `/tmp/oc-triple-current-20261015`。本结论只接受三项交付的有界现状，不构成完整生产接线或 develop 发布批准。
