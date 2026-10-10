# QUALITY-LINT-BASELINE

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
