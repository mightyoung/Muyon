# OC13 / OC14 / CR10F3 独立复验（2026-10-14）

本任务只独立复验，不合入 develop/main；原作者分支、已有工作区和活动 writer 保留。

## 固定身份及组合基线

| 对象 | 完整 SHA |
|---|---|
| OC13 task/oc-13-probe-throws | `c3fe22b5769016fc6e686f290213a52941dadb3f` |
| OC14 task/oc-14-update-value-semantics | `4b68b09be94463e19912e2469036e7435b3d4104` |
| CR10F3 task/cr10-f3-folio-taint-probe | `9f5216bb3768deb84522fb6c91415442f9ad6268` |
| 最新 develop / 本轮受测代码 | `01e56cc2d729dab70e1b1def05c3aa93b28f421a` |

远端完整 SHA 已重复核对；三个固定源没有被替换。develop 已从委托已知的
`2224c6faca32c28ebdaa148d741b1a618df87987` 前进，且已含此前三项组合合入
`52250649d34b4983929daf815430a0c6789d16db`。原任务提交是被摘入，不要求其原 SHA 成为 develop 祖先。

独立分支 `review/oc-triple-independent-20261014` 从精确最新 develop 建立，
没有重复 cherry-pick，也没有产品改动。OC13、OC14 测试文件与各固定源 Git blob 相同；
CR10F3 九文件中八文件相同，唯一变化是 adapter 后续新增 WC-D 只读回执能力，
activate/probe 接线未变。范围检查用上述完整 SHA，避免旧 origin/develop 缓存误报。

已读三份固定源任务书、REVIEW、GB-1 不变量审计、CR-10/CR-11、CR14 实施设计、
ADR-0001/0002/0004。仓库固定源及工作区未发现 AGENTS.md 或 SKILL.md；
/workspace/.agents、.codex 为空。依 REVIEW 委派非作者核实子代理，在隔离工作区执行；
本轮未采用额外技能。

## 目标测试与逆变异

Flutter 3.47.5 / Dart 3.13.4，Linux x64，缓存依赖离线解析。
从 apps/muyon 执行：

```sh
flutter test --no-pub --reporter json \
  ../../packages/muyon_ui/test/dynamic_external_content_default_test.dart \
  test/oc14_update_value_semantics_test.dart \
  test/inquiry_host_taint_probe_test.dart \
  ../../packages/inquiry_module/test/host_taint_probe_test.dart \
  ../../packages/inquiry_module/test/assistant_permission_hosted_test.dart
```

本轮首次 GREEN 与全部变异恢复后 GREEN 均终态 exit 0，**39 pass / 0 skip / 0 fail**。
每次逆变异仅一处、替换次数断言为一、finally 恢复原字节：

| 逆变异 | 本轮实际结果 |
|---|---|
| OC13 surface getter catch true → false | exit 1，2 pass / 2 fail；两个新增测试均 Expected true / Actual false。 |
| OC14 update_record allowClear true → false | exit 1，6 pass / 1 fail；explicit null 清空例 Expected succeeded / Actual failed。 |
| CR10F3 facts.requiresConfirmation → false | exit 1，6 pass / 4 testDone failure；三项读值断言 Expected true / Actual false；widget 例期望外部内容提示一项，实际零项。 |
| CR10F3 probe catch null → false | exit 1，9 pass / 1 fail；read failure 例 Expected null / Actual false。 |

恒 clean 变异的 widget 失败已核实为提示缺失断言；没有清理超时，未把额外异常打印计成更多行为。
原作者 RED12fail 含清理超时连锁，仍不作为十二个独立行为证据。
本地 muyon_ui `flutter analyze --no-pub --fatal-infos` 终态 exit 0，No issues found（14.7s）。
首次 analyze 因只读 HOME 下 .dartServer 缓存创建失败而 exit 255，未产生代码诊断；
改用分析器官方 ANALYZER_STATE_LOCATION_OVERRIDE 指向仓库外状态目录后通过，
未改 HOME、产品或 analyzer 配置。

离线 pub get 自动改动的三份 analysis_options 已恢复。
变异恢复后的 git status 为空、产品 diff 为空、git diff --check 通过。
原始测试、变异与 analyze 输出只在仓库外，未提交。

## 精确 CI 终态

[最新 develop 组合 CI 38279219941](https://github.com/mightyoung/Muyon/actions/runs/38279219941)
**completed/success**，job `114912109725`，2026-10-12 17:01:18 UTC 完成。
本轮重新读取完整解码 job 日志，核对 checkout 精确为 `01e56cc2d729dab70e1b1def05c3aa93b28f421a`。
8/8 analyze、8/8 suite、Doctor 23、Laya、coverage 均成功。

| 套件 | pass | skip | fail |
|---|---:|---:|---:|
| module_api | 276 | 0 | 0 |
| muyon_ui | 392 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 365 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 2312 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |

合计 **4199 pass / 207 skip / 0 fail**。当前 module_api 276 例覆盖旧源 198 与原组合 250 之后的契约。
平台、golden 和真实模型 skip 不算相应能力验收。

[CR10F3 source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069)
再次核对 `9f5216bb3768deb84522fb6c91415442f9ad6268`，completed/success；不把 source CI 当作最新组合证据。
最新组合产品代码已经有上述同 SHA 完整 CI，本轮报告使用 [skip ci]，不为纯报告重复门禁，
也不把报告提交 SHA 冒称为 CI 受测代码 SHA。

## 结论及条件

**三项有界交付在最新 develop 上独立复验通过，无新增产品阻断。**
已合入部分不需再次合入；本验证者没有 merge develop/main。
后续集成人若变更产品或组合基线，需重新验证对应精确 SHA。

OC14 如实锁定省略保留、null/空串清空、0 保存、false 拒绝、[] 替换、空 values 拒绝。
false 在公开 schema 层拒绝，未证明 boolean normalizer 保存。
两项负例仅锁异常类型，进一步断言 invalid_parameters 是非阻断测试加强建议。

CR10F3 生产 activate 仍只传 probe，未传 task/conversation；
AppState 缺身份、unknown 或读取失败均强制确认。这是可接受安全退路，
**不是完整生产身份接线、非宿主污染继承或真实模型验收**。
委托已知的旧 develop 2380 元数据断言误报归其他 writer，本轮不改、不据 CI 通过宣称其独立修复完成。

外仓身份、CI 与逐测试摘要位于 /workspace/reports/oc-triple-independent-20261014。
未运行真实模型/Android，未导出 MUYON_EVAL_REAL；未改作者分支、forcepush、delete 或 deploy。

## 最新 develop 身份补核

远端再次读取：develop 已为 `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`，
三个作者分支仍为上表完整 SHA，原报告提交为 `f036903835e2f02d7831ac9c5c1298894eac8597`。
`git diff --name-only 01e56cc2d729dab70e1b1def05c3aa93b28f421a 1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d -- apps packages .github pubspec.yaml pubspec.lock scripts/ci.sh`
exit 0、输出为空：本次前进未改变受测产品、依赖清单或 CI 工作流。

原独立工作区以原文相同五文件命令新跑目标测试，exit 0、39 pass / 0 skip / 0 fail；
这是代码等价基线的本地复跑，不冒称在新 SHA 工作区执行。工作区仍干净，原始 JSON 日志留仓库外。
逆变异继续引用前文实际执行证据，未重复施加或增加失败数。

[最新 develop CI 38493563519](https://github.com/mightyoung/Muyon/actions/runs/38493563519)
精确 head SHA `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`，completed/success，
2026-10-14 01:22:33 UTC 终态。`gh run view --json headSha,status,conclusion,url,updatedAt`
重新读取 exit 0；完整解码日志 SHA-256 `5866a89941633a8a07038735f0ba8d90729d75ceb83c1c2c1b68cce46e3fea6a`
已与外仓证据核验相同，checkout 完整 SHA 存在；八套计数仍为 4199 pass / 207 skip / 0 fail，
module_api 276。此最新组合没有新增产品阻断；生产身份接线及 unknown 强制确认边界保持前文结论。
本补核只更新独立 review 报告，不执行 develop/main 合入。

