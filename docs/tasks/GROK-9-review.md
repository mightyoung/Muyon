# GROK-9 审查（leader A，2026-10-10）

提交 `9a78cfe` · 结论：**通过，可合入**。

- 方案：扫出 18 个超过 800 行的文件（比任务列的 7 个多 11 个），每个都有行号分块、拆分建议、耦合点、必须原样搬运的安全行、调用方与测试、风险等级；建议顺序由低风险到授权 / 事务路径。
- `agent_eval.dart` 拆分（`554c8ef`）：用 `part` / `part of`，父文件保留原 import 与 `export`，公开导入路径不变。审查方独立复核：
  - 搬运核对：拆分前后去掉空行与 `import/export/part` 行后排序比对，1140 行**完全一致**；
  - `apps/muyon` 下 `flutter analyze` 无问题；`agent_eval_test.dart`、`agent_eval_stream_capture_test.dart`、`confirm_title_test.dart` 共 43 通过、1 跳过（原有）；
  - `dart format` 检查 7 个文件无变化；拆后最大文件 363 行。
- 后续派工时的注意（不阻断）：
  1. `surface.dart` 要等 SN-1（动态确认卡外部内容标记）合入后再拆，避免冲突；
  2. `agent_dispatch.dart`、`agent_model_turn.dart` 没有直接测试，拆之前先补测试；
  3. 授权 / 事务类文件（`tool_registry`、`foundation_repository`、`transfer_service` 等）按方案放在最后，每个文件单独成片，并沿用这次的排序比对作为搬运证明。
