# OC13 / OC14 / CR10F3 独立组合复验（2026-10-15）

结论：三项有界交付在当前 develop `3b4a7b27afded3f2d3007028d793aa06bd564312` 上复验通过，无新增阻断。三项此前已合入，无需重复摘取。本任务只有独立复验权限，不合入 develop/main。

## 固定来源与组合身份

| 对象 | 完整 SHA |
| --- | --- |
| OC13 | `c3fe22b5769016fc6e686f290213a52941dadb3f` |
| OC14 | `4b68b09be94463e19912e2469036e7435b3d4104` |
| CR10F3 | `9f5216bb3768deb84522fb6c91415442f9ad6268` |
| 本轮受测 develop | `3b4a7b27afded3f2d3007028d793aa06bd564312` |

远端首末核对一致，三个固定源均为本轮基线祖先。OC13、OC14 测试与源逐字相同；CR10F3 九文件中八个 blob 与源一致，adapter 后续加入 WC-D 只读回执能力。相比此前受测 `325e798d37044cbc0617f5bddbd14ccb9adec390`，apps、packages、CI 与依赖清单 diff 为空。

分支 `review/oc-triple-independent-20261015`，独立工作区 `/tmp/Muyon-oc-triple-independent-20261015`。已查任务书、REVIEW、不变量审计、关联 CR10/CR11/CR14 设计与 ADR；未找到适用 AGENTS.md / SKILL.md，工作区 .agents / .codex 为空。按 REVIEW 委派非作者核实代理进行静态核对和实际测试。

## 实跑与必要逆变异

Flutter 3.47.5 / Dart 3.13.4，Linux；离线 pub get 成功，其生成的三份 analysis_options 修改已恢复。首次原生依赖加载因 PDFium 下载失败，0 testDone、无 done 终态，单独记为环境失败，不计行为 RED。仅校验并复用已有 PDFium / SQLite 原始库缓存，未复制旧 package_config 或 hook metadata。

从 apps/muyon 运行五个目标文件：dynamic_external_content_default、oc14_update_value_semantics、inquiry_host_taint_probe、inquiry_module/host_taint_probe、assistant_permission_hosted。新鲜首次与全部恢复后均 exit 0，**39 pass / 0 skip / 0 fail**。

| 临时单点逆变异 | 实际终态与失败依据 |
| --- | --- |
| OC13 getter catch true → false | exit 1，2P/2F；抛错与恢复两例 Expected true / Actual false。 |
| OC14 allowClear true → false | exit 1，6P/1F；显式 null 清空例 Expected succeeded / Actual failed。 |
| CR10F3 facts.requiresConfirmation → false | exit 1，6P/4F；三个读值断言与一个 widget 提示诊断，不能称四个独立安全行为。 |
| CR10F3 probe catch null → false | exit 1，9P/1F；读取失败例 Expected null / Actual false。 |

四轮均 finally 恢复原字节。muyon_ui 严格 `flutter analyze --no-pub --fatal-infos` exit 0，No issues found（7.0s）。报告写入前工作树干净；报告写入后仅此文档新增，产品 diff 为空，git diff --check 通过。

## 精确组合 CI 终态

本轮重新获取 [CI 38611422181](https://github.com/mightyoung/Muyon/actions/runs/38611422181) 元数据、job 116015476530 的完整 decoded 日志与 coverage suite outcomes：head/checkout 均精确为上述 3b4a7b27 完整 SHA，首次 attempt **completed/success**，2026-10-14T18:20:10Z 终态。8/8 analyze、8/8 suites、Doctor 23、Laya 与 coverage 全部成功，**4199 pass / 207 skip / 0 fail**。

八套计数：module_api 276；muyon_ui 392P/152S；prototype 39P/1S；research 365P；supplier_core 498P/4S；host 2312P/3S；ui_preview 15P；inquiry 302P/47S。skips 不算平台、golden、真实模型能力验收。源 module_api 198 与旧组合 250 不能代替当前 276 的组合证据。

[Source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069) 也重新核对为 exact `9f5216bb3768deb84522fb6c91415442f9ad6268`、attempt 1、completed/success。因三项已合入且现有 CI 精确匹配当前组合，本次不重复触发相同代码全量 CI。纯报告提交采用 [skip ci]，报告提交 SHA 不冒称受测代码 SHA。

## 交付判断与条件

OC13 满足两个独立探针测试与 catch false 变异失败要求。OC14 如实锁定省略保留、null/空串清空、0 保存、false 在公开 schema 层拒绝、[] 替换、空 values 拒绝；false 不构成 boolean normalizer 保存证明，符合任务「失败照实记录、不改源码」停止条件。测试文件第13行关于 false 经 normalizer 的注释应澄清为 schema 提前拒绝；负例进一步细化 invalid_parameters，两者均为非阻断建议。

CR10F3 的宿主探针、缺失/unknown/身份不匹配/抛错强制确认与 hosted bypass→confirmWrites 退路通过。生产 activate 仍只传 probe，**未传 task/conversation**，不称完整生产身份接线、非宿主污染继承或真实模型验收。作者 RED12fail 含清理超时连锁，不作十二个独立行为证据。已知宿主 2380 断言基线由其他任务处理，本轮不重复修，也不据此宣称其修复完成。

若后续改产品或组合基线，应重核完整 SHA 并运行对应验证。当前已合入的三项无需再合入，本报告不是整体 develop 发布批准。

原始日志仅放仓库外 `/tmp/oc-triple-independent-20261015`，持久摘要 `/workspace/reports/oc-triple-independent-20261015`。未真实模型/Android、未导出 MUYON_EVAL_REAL，未 merge develop/main、forcepush/delete/deploy；所有原作者分支和 writer 保留。
