# 验证备忘录

## AUTH-1b C2：本次接受 Mac 截图基线例外

2026-10-08，用户明确接受本次限定基线例外，允许发布已审查的 C2 集成提交 `ffe6be31a8a4cb516f8bcc5331a3065cbc142dcd` 到 develop，并要求后续验证回归。该决定仅适用于本次已逐项对照的既有截图失败，不是以后失败的自动豁免。main/release 不在本次授权内。

### 已核实事实

- 未合 C2 的精确 develop 基线为 `4573adb73f32526bc3f3bab8125db923e474f890`。同一 Mac 环境下完整 Inquiry 套件为 281 通过、1 跳过、46 失败；C2 集成结果相同。
- 46 个失败用例集合完全一致，无新增、减少或变化。46 张失败图的尺寸和差异像素数一致；实际图、基线图、isolatedDiff、maskedDiff 共 184 张 PNG 的 SHA256 全部一致。基线日志的 46 项差异像素数也与图像计算值一致。
- Inquiry、UI 包及 pubspec.lock 与上述基线一致；未改 golden、跳过条件、断言或容差。
- 精确 C2 集成 SHA 的 [Linux CI 37786931707](https://github.com/mightyoung/Muyon/actions/runs/37786931707) 已成功：分析 7/7，测试套件 7/7，doctor 23 场景和 Laya 步骤通过。Inquiry 为 281 通过、47 个既有平台条件跳过；这不能代替 Mac 截图验证。
- 本地 strict 零问题，七包分析及其余六个套件通过（含宿主 1136 通过、3 个既有跳过）；**Mac 全量 verify.sh 仍退出 1，截图根因未知，不能记为全绿**。

原始日志、比较脚本和完整哈希矩阵不提交。逐项证据在当时的 `/tmp/AUTH-1b-C2-baseline-nonregression-ffe6be31.md`、`/tmp/auth-c2-golden-4573-comparison.json` 和 `/tmp/auth-c2-golden-4573-comparison.md`；临时文件可能失效，后续需重新生成证据。范围与审查见 [C2 审查记录](AUTH-1b-model-policy-review.md) 和 [AUTH 一页总结](AUTH-1b-summary.md)。

### 后续验证必须回归

- 在相同平台和工具链重跑完整 Inquiry 与全仓 verify.sh；本次主机为 macOS 27.0.1（26A434）、arm64，测试 engine 使用 SDK 内的 darwin-x64；工具链为 Flutter 3.47.5 / Dart 3.13.4。使用同一绝对 SDK、同一字体与渲染环境，从 apps/muyon 运行 Inquiry，取消代理并设 NO_PROXY=localhost,127.0.0.1,::1。记录 OS、架构、SDK/engine、字体版本和命令。
- 同时保留未改基线与待验版本的终态、完整失败用例集合、像素差异数和四类 PNG 哈希，检查是否出现新增、减少或变更。
- 排查工具链、字体与渲染等因素，确认根因后再决定处理；**不得通过更新 golden、增加跳过、提高容差或放宽断言掩盖问题**。如仍失败，继续明确报告失败，不能沿用本次例外自动宣称通过。

UI/profile 授权入口、其他模块业务闭环、真实云模型和实机仍后置；本次例外不改变这些范围。
