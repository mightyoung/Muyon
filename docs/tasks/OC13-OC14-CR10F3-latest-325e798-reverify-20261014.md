# OC13 / OC14 / CR10F3 最新组合独立复验

日期：2026-10-14。只独立复验和提交 review 报告，不合入 develop/main，不改作者分支或产品代码。

## 固定身份与范围

远端完整 SHA 本轮重新核对：

| 对象 | 完整 SHA |
| --- | --- |
| OC13 | `c3fe22b5769016fc6e686f290213a52941dadb3f` |
| OC14 | `4b68b09be94463e19912e2469036e7435b3d4104` |
| CR10F3 | `9f5216bb3768deb84522fb6c91415442f9ad6268` |
| 最新 develop / 本轮受测 HEAD | `325e798d37044cbc0617f5bddbd14ccb9adec390` |

三个作者分支未被替换。三项交付已被摘入 develop；不重复 cherry-pick。
新独立工作区 `/workspace/Muyon-oc-triple-latest-325e798-20261014`，分支
`review/oc-triple-latest-325e798-20261014`，从上述最新完整 SHA 建立。
相对此前 develop `1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d`，
apps、packages、依赖清单和 CI 文件 diff 为空。

已读固定源 OC-13、OC-14、CR10-F3 任务书及 REVIEW、GB-1 不变量审计、
CR-10、CR-11、CR14 设计、ADR-0001/0002/0004。AGENTS.md / SKILL.md 未发现，
/workspace/.agents 与 .codex 为空。按 REVIEW 委派非作者代理执行代码与运行核实。
作者十一交付文件中十个 blob 相同；adapter 后续新增 WC-D 只读回执能力，
原 activate/probe 接线未变。五目标测试与此前固定 develop 的 blob 全相同。

## 本轮实际测试与逆变异

Flutter 3.47.5 / Dart 3.13.4，Linux x64。新工作区离线 pub get；
自动改动的三份 analysis_options 恢复。首次环境只读配置失败及原生资产下载失败均保留，
加载前失败无行为 testDone，不计行为 RED。仅复用已有 PDFium / SQLite 二进制缓存，
逐一 SHA256 核对一致；没有复制旧 package_config 或 hook 输出。

从新树 apps/muyon 执行：

```sh
flutter test --no-pub --reporter json \
  ../../packages/muyon_ui/test/dynamic_external_content_default_test.dart \
  test/oc14_update_value_semantics_test.dart \
  test/inquiry_host_taint_probe_test.dart \
  ../../packages/inquiry_module/test/host_taint_probe_test.dart \
  ../../packages/inquiry_module/test/assistant_permission_hosted_test.dart
```

首次 GREEN 与全部恢复后 GREEN 均 exit 0，**39 pass / 0 skip / 0 fail**。
每次变异断言只替换一处，finally 恢复原字节：

| 逆变异 | 终态与失败依据 |
| --- | --- |
| OC13 getter catch true → false | exit 1，2P/2F；throwing 与 recovering 两例 Expected true / Actual false。 |
| OC14 allowClear true → false | exit 1，6P/1F；explicit null clears contact phone and quotation notes，Expected succeeded / Actual failed。 |
| CR10F3 facts.requiresConfirmation → false | exit 1，6P/4F；三项实时读值 Expected true / Actual false，加外部内容提示缺失断言。 |
| CR10F3 probe catch null → false | exit 1，9P/1F；read failure 例 Expected null / Actual false。 |

muyon_ui strict `flutter analyze --no-pub --fatal-infos` exit 0，No issues found（8.5s）。
最终报告写入前 git status 空、git diff --check 通过；未遗留变异或产品改动。
原始日志仅位于仓库外 `/workspace/reports/oc-triple-latest-325e798-20261014`。

## 精确组合 CI

[CI 38500307094](https://github.com/mightyoung/Muyon/actions/runs/38500307094)
重新读取元数据与完整解码 job 日志（job 115645421285），checkout 精确为上述 325e798 完整 SHA。
**completed/success**，2026-10-14 02:37:32 UTC 完成；8/8 analyze、8/8 suites、
Doctor 23、Laya、coverage 步骤通过。八套计数为 module_api 276、muyon_ui 392/152skip、
prototype 39/1skip、research 365、supplier_core 498/4skip、host 2312/3skip、
ui_preview 15、inquiry 302/47skip：**4199 pass / 207 skip / 0 fail**。
平台、golden、真实模型 skips 不算能力验收。module_api 276 已覆盖旧源 198 / 原组合 250 后的契约。

[CR10F3 source CI 38132458069](https://github.com/mightyoung/Muyon/actions/runs/38132458069)
重新核对 exact `9f5216bb3768deb84522fb6c91415442f9ad6268`，completed/success；不代替最新组合 CI。
纯报告提交采用 [skip ci]；报告 SHA 不冒称 CI 受测代码 SHA。

## 结论与条件

三项有界交付在最新 develop 上独立复验通过，**无新增产品阻断**。已合入部分无需重复合入；
如集成人进一步变更产品或组合基线，应重新核对精确 SHA 并运行对应验证。

OC14 锁定省略保留、null/空串清空、0 保存、false 拒绝、[] 替换、空 values 拒绝。
false 在公开 schema 层拒绝，不是 boolean normalizer 保存证明。
负例进一步断言 invalid_parameters 为非阻断测试加强建议。

CR10F3 生产 activate 仍只传 probe，未传 task/conversation；缺身份、unknown、读取失败均强制确认。
这是安全退路，**不称完整生产身份接线、非宿主污染继承或真实模型验收**。
作者 RED12fail 含清理超时连锁，不作十二个独立行为证据。
旧 develop 宿主 2380 断言误报由其他 writer 处理，本轮不重复修、不以 CI 通过宣称该修复完成。

未运行真实模型或 Android，未导出 MUYON_EVAL_REAL；未 merge develop/main，
未 forcepush/delete/deploy，所有原作者工作区和活动 writer 保留。
