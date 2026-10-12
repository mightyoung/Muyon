# OC13 / OC14 / CR10F3 最新 develop 独立复验（2026-10-12）

本轮只独立复验，不执行 develop/main 合入。所有原作者工作区与分支保留。

## 身份与范围

两次远端完整 SHA 核对一致：
- OC13 `c3fe22b5769016fc6e686f290213a52941dadb3f`。
- OC14 `4b68b09be94463e19912e2469036e7435b3d4104`。
- CR10F3 `9f5216bb3768deb84522fb6c91415442f9ad6268`。
- 最新 develop 与本轮受测代码基线 `9d8a4118de74cda369ddd004c519d01a1e0752ba`。

develop 已包含此前三项组合合入 `5225064`。因此新建隔离分支
`review/oc13-oc14-cr10f3-reverify-20261012`，从最新 develop 直接复验已组合代码，
没有重复 cherry-pick 或修改产品代码。OC13/OC14 测试与固定源逐字一致；
CR10F3 九文件中八文件逐字一致，唯一后续改动为 inquiry adapter 的 WC-D 只读回执能力，
其 activate/probe 接线未改变。证据 JSON 在仓库外 `/workspace/reports/oc-triple-reverify-20261012`。

已读固定源 OC-13、OC-14、CR-10 任务书，REVIEW、GB-1 不变量审计、CR-10/CR-11 审计、
CR14 实施设计及 ADR-0001/0002/0004；未发现仓库 AGENTS.md 或 .agents/skills，
/workspace/.agents 与 .codex 为空。按 verification-before-completion 做恢复后验证。

## 新鲜本地证据

Flutter 3.47.5 / Dart 3.13.4，Linux x64，实际命令从 apps/muyon 执行：
`flutter test --no-pub --reporter json ../../packages/muyon_ui/test/dynamic_external_content_default_test.dart test/oc14_update_value_semantics_test.dart test/inquiry_host_taint_probe_test.dart ../../packages/inquiry_module/test/host_taint_probe_test.dart ../../packages/inquiry_module/test/assistant_permission_hosted_test.dart`。

全部逆变异恢复后的终态 **39 pass / 0 skip / 0 fail，exit 0**。
临时逆变异每次一处并在 finally 恢复原字节：

| 变异 | 实际检测 |
|---|---|
| OC13 getter catch true→false | exit 1；抛错与恢复两例均 Expected true / Actual false。 |
| OC14 update_record allowClear true→false | exit 1；显式 null 清空例 Expected succeeded / Actual failed。 |
| CR10F3 facts.requiresConfirmation→false | exit 1；真实污染、unknown、attach 透传三例 Expected true / Actual false；另有真实卡片 widget 错误。仅报告三项 testDone failure 与额外错误，不夸为四个独立失败终态。 |
| CR10F3 catch null→false | exit 1；读取失败例 Expected null / Actual false。 |

本地 `muyon_ui/flutter analyze --no-pub --fatal-infos` exit 0、No issues found。
变异恢复后与写报告前 git status 为空、产品 diff 为空、git diff --check 通过；
pub get 自动改动的三个 analysis_options 已恢复。原始测试/analyze/CI 日志留 /tmp，不进仓库。

## CI 终态

独立重新读取完整 job 日志并核对 checkout SHA：
[最新 develop 组合 CI 38196079614](https://github.com/mightyoung/Muyon/actions/runs/38196079614)，
headSha 精确为 `9d8a4118de74cda369ddd004c519d01a1e0752ba`，
**completed/success**，2026-10-12 02:52:39 UTC 完成。
8/8 analyze、8/8 套件、doctor 23、Laya 与 coverage 成功；
4043 pass / 207 skip / 0 fail；其中 module_api **274 pass / 0 skip / 0 fail**，
覆盖了旧 source 198 与前次组合 250 之后的当前契约。
muyon_ui 387 pass / 152 skip / 0 fail。平台与真实模型 skip 不是对应能力验收。

[CR10F3 source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069)
再次核对完整 headSha `9f5216bb3768deb84522fb6c91415442f9ad6268`、completed/success。
本轮复用受测最新组合的精确 SHA 证据，不为纯报告重复跑全量 CI，
报告提交不冒称产品代码受测 SHA。

## 结论与剩余边界

**三项有界交付在最新 develop 上复验通过，无新增阻断。** 已在 develop 中的三项不需重复合入；
本验证者本轮没有 merge develop/main。
OC14 如实锁定省略保留、null/空串清空、0 保存、false 拒绝、[] 替换、空 values 拒绝。
false 在公开 schema 层拒绝，未证明 boolean normalizer 保存；两项负例只锁异常类型，
细化 invalid_parameters 仍是非阻断测试建议。

CR10F3 生产 activate 仍只传 probe，未传 task/conversation；
AppState 缺身份返回 true，unknown/抛错强制确认，安全退路已验证；
**不是完整生产身份接线、非宿主污染继承或真实模型验收。**
原 RED12fail 含清理超时连锁，不能作为十二个独立行为证据。
已知 2380 宿主断言误报由其他 writer 处理，本轮不改；本次 CI 未失败不替代其独立修复结论。
不把上述三项有界通过扩展为整个 develop、AIUI 或其他并行交付的发布批准。
未运行真实模型/Android，未导出 MUYON_EVAL_REAL；未 forcepush/delete/deploy。

## 追加当前 develop 复验

远端 develop 已前进为 `1a0131866ab33d87462ca49b3e4d75264b55e36a`。
独立分支 `review/oc-triple-current-1a01318-20261012` 的目标测试新鲜执行 **39 pass / 0 skip / 0 fail，exit 0**。
此前四项实际失败逆变异涉及的生产与目标测试文件，与前次基线 Git blob 全部精确一致；未重复修改产品代码。三个作者远端完整 SHA 再次核对均未替换。
[当前组合 CI 38200781619](https://github.com/mightyoung/Muyon/actions/runs/38200781619) checkout 精确为上述完整 SHA，completed/success，2026-10-12 04:02:39 UTC 完成；8 analyze、8套件、Doctor23、Laya、coverage均成功，**4065 pass / 207 skip / 0 fail**，module_api274。
测试结束工作树干净。CR10F3未知身份强制确认、非完整task/conversation生产接线及RED12连锁限制不变。本次只提交报告、不合入develop/main。
