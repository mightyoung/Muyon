# QUALITY-LINT-BASELINE

历史归档：本文及 diagnostics/owner.patch 冻结原 PR22 的旧源诊断，不代表当前
develop 门禁。旧90项已由后续 owner 与当前组合处理；patch 仅留档，不得重复应用。
当前修复与复审见 [CURRENT交接](QUALITY-LINT-CURRENT-2026-10-10.md) 和
[CURRENT复审](QUALITY-LINT-CURRENT-review.md)。下文保留原采样措辞。

授权：用户要求制定修复任务并并行开始执行修复；本片独立分支
`task/quality-lint-baseline`，基线 develop
`8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d`。

## 交付与范围

- 为 muyon_module_api、supplier_core、muyon_ui、prototype_module 显式启用
  `package:flutter_lints/flutter.yaml`，与已有四包的 6.x 推荐基线一致。
- 前两包补直接 dev dependency；后两包已有声明。workspace lock 已解析
  flutter_lints 6.0.0 / lints 6.1.0，不升级版本。Actions pub get 核实一致性。
- 采用包内显式 include，避免根配置继承影响其他包及脚本，包单独分析也可见配置。
  不添加 ignore/exclude、不关闭规则、不改变 fatal infos/warnings 默认值。
- 先独立提交配置，保留首次真实 diagnostics；再做保持语义的最小局部修复。
  不修改其他 owner 的 AIUI API snapshot/plan/validation/state/stream/controller、
  widgets、Dream/foundation、agent_resume/tool_registry、supplier_core LAN 文件；
  涉及这些文件的 diagnostics 与逐项修复建议交父任务和对应 owner。
- 不改 ci.sh，不做全库格式化、rename、架构拆分；原始日志仅保留 Actions 或 /tmp。

## 回归计划与完成判据

本环境无 Flutter/Dart，使用现有 `.github/workflows/ci.yml`，Flutter 3.47.5。
首次配置提交的 CI 红是新基线诊断证据，不视为通过或忽略失败。
收集每条 diagnostic 的路径、行号、规则和 owner；对范围内文件最小修复，
对争用文件只给 patch 建议。最终精确 source 与 integrator 组合均需
`bash scripts/ci.sh`：8/8 analyze、8/8 test suites、gate/doctor，以及已有
Laya tests 通过。Linux/macOS 原有验收边界保持，不把 Linux 跳过的 golden 当验收。

父任务按 REVIEW.md 独立审查，唯一 integrator 合 develop；本片只提交、推送和草稿 PR。

## 执行证据与协调

首次固定配置源 `5fbc6ce83d569614cd9fd8497f68acc60c495201` 的
[push CI 38022202677](https://github.com/mightyoung/Muyon/actions/runs/38022202677)
失败：四个新基线包 294 条 info（45/37/2/210）；已有四包 analyze 通过；
test 8/8、gate 9/9、doctor 23/23 通过，后续 Laya 被失败门禁跳过。
逐项位置见 [diagnostics](QUALITY-LINT-BASELINE-diagnostics.md)，不把预期红视为通过。

局部修复针对 204 条无争用 diagnostics，包括 175 个块边界，未改条件或调用顺序；
SQLite migration 夹具改按字段名 `value` 访问 Row；crypto 3.0.7 补为 supplier_core
直接 dev dependency，workspace lock 原已解析同版本，不升级依赖。
null-aware collection 保持空值跳过语义、单次求值；私有 named initializing formals
要求 Dart >=3.12，项目 SDK >=3.13，调用方公开参数名保持不变。
基准输出用 stdout.writeln 保留输出，不关闭 avoid_print。

90 条争用 diagnostics 在 [候选 patch](QUALITY-LINT-BASELINE-owner.patch)，
API/UI/LAN owner 在其最新代码适配、验证，父任务协调；本分支未修改这些 Dart 文件。
44 个局部修复文件均由实际诊断驱动，无全库格式化或改名。
局部修复精确 source `9b93e2383a2cc35163dcd3b1c1bb472a05534531` 已启动完整 CI，
其终态与 owner 修复后的组合 GREEN 仍须补核。本任务保持草稿，不合 develop/main。

局部修复后的[精确 push CI 38023275222](https://github.com/mightyoung/Muyon/actions/runs/38023275222)
已 completed/failure：analyze 5/8，只剩 module_api 44、muyon_ui 37、supplier_core 9；
逐条 `(file,line,column,rule)` 与首次保护清单完全相同，204 条局部诊断消除、无新增诊断。
test 8/8（module_api +68、UI +323/152skip、prototype +39/1skip、research +220、
supplier +490/4skip、host +1459/3skip、preview +15、inquiry +289/47skip），
gate 9/9、doctor 23/23 通过；Laya 因 analyze 失败仍被跳过，不冒称完整门禁 GREEN。
后续提交仅任务证据与候选 patch 的空白修正，产品/依赖/CI 树与该已测 source 相同。
最终 GREEN 阻断是 90 条跨 owner 项；需对应 owner 应用并验证，然后 integrator 全量组合验证。
