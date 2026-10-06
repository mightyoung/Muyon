# P0-4 审查（第一批证据）

审查分支 `review/P0-4` @ `f535db4`（与 `task/p0-4-evidence` 相同）· 审查 leader（接任）· 核实子代理 Opus · 2026-10-06

## 范围
只新增 4 个文件（+503 行），没有越界：两个链路证据 JSON、`p0-evidence-2026-10.md`、`tool-selection-llm-baseline-deepseek-chat.md`。运行基于 `6d21831`，**早于 P0-3c 合入（`1211bf0`）**。

## 核实结果

| # | 第 5 节要点 | 结论 | 依据 |
|---|---|---|---|
| 1 | 不得出现密钥，端点只保留到路径 | 满足 | `.env` 两个密钥的完整值、前 10 位、后 10 位在 4 个文件、整棵树和提交补丁中都是 0 命中；`sk-`、`Bearer`、`Authorization` 等模式 0 命中；端点只有 `https://api.deepseek.com/chat/completions` |
| 2 | 基线每模型一次、不挑结果、指标齐全 | 满足 | 由逐题表 140 行复算：top-1 66、弃权 26/26、误选写入/外发 0、平均 1222.4 ms、p50/p95 一致（差异只来自取整）。用量无逐题列，不能复算，量级合理 |
| 3a | `evidenceClass: real-model` 且 `passed: true` | 部分满足 | 两次都是 real-model，但都 `passed: false` |
| 3b | `readResultsChecked` 含 `compare_quotes`、`project_budget` | 不满足 | 链路在预算题失败后停止，没有这个字段 |
| 3c | `tasks[].tools` 与逐题判定一致 | 部分满足 | 比价题两次都对；预算题第 1 次有工具但失败，第 2 次为空 |
| 3d | `write.repeatConfirmRefused` 为 true | 不满足 | 没走到写入 |
| 4 | 平台分开，无头不写成真机 | 满足 | `binding: "flutter_test (headless)"`，汇总写明不是 R 证据；Windows 写「未验证」 |
| 5 | `verify.sh` 不导出 `MUYON_EVAL_REAL` | 基本满足 | 汇总只写了「去掉模型变量」；host 跳过 2 个用例，与没有真实请求一致 |
| 6 | 夹具不写成真实证据 | 满足 | 两次失败运行都标为「不计为 M 证据」 |

- **重跑 verify.sh**（没有导出任何 `MUYON_*`）：analyze 7/7；各套件通过数与汇总一致。整轮中 module_api、muyon_ui 显示 NO SUMMARY，单独重跑 +17、+6 全部通过，判断为机器负载导致。
- **run2** 是第 1 次失败约 40 秒后的立即重跑，两次都如实入库，没有挑结果。

## 结论
- **退出标准第 2 项**：基线报告可作为 M 证据入账。
- **退出标准第 1 项**：这一批**不能**入账。没有任何 `passed: true` 的链路运行，也没有真机证据。
- 两次失败运行和 D1 是如实的负面证据，保留。

## 本轮修改（engineer，在 `review/P0-4` 上，只改 `p0-evidence-2026-10.md` 与两个链路 JSON）

**应改**
- **S1 本机路径。** 两个 JSON 的 `failureStack` 含 `/Users/<用户名>/Downloads/dev/muyon-worktrees/b-ui/...`，违反「不入库个人数据」。把这个前缀统一替换为 `<worktree>/`，其余内容一字不动；在汇总里写明做过这一替换。另外补一句运行时的工作区和 `git status` 状态（`commit` 字段是手工传入的，需要说明当时代码就是干净的 `6d21831`）。
- **S2 注明运行早于 P0-3c。** 在汇总里写明两次链路运行基于 `6d21831`，早于 P0-3c 合入。
- **S3 补写 run2 的原因。** run2 是失败后的立即重跑，不是网络或限流原因，两次都如实记录。
- **S4 写明 verify 环境。** 改为「未设置 `MUYON_EVAL_REAL` 及任何 `MUYON_EVAL_MODEL_*`」。

**可选（记录）**
- **O1** 第 1 次运行预算题的 `answerPreview` 是 `inquiry.project_budget` 的工具说明文字，不是模型回答，读起来会误导。链路脚本取预览的问题，并入 P0-3d 一起看。
- **O3** 文件名多了 `headless`，保留。

## D1 的处理
D1（deepseek-chat 在预算题上不按助手协议回答 JSON：一次纯文本，一次 DeepSeek 原生工具调用标记 `<｜｜DSML｜｜ calls>`）是真实缺陷，不修就无法得到 `passed: true` 的链路证据。另开 **[P0-3d](P0-3d.md)**（senior）修复。

## 下一批（P0-3d 合入之后）
在 `develop`（含 P0-1、P0-3c、P0-3d）上：
1. 无头链路重跑一次（不挑结果，失败也入库）；
2. Android 真机 vivo V2324A 链路（设备重新连接后）；运行后卸载测试包；
3. `bash scripts/ci.sh` 一次，附摘要行；
4. macOS 设备集成测试需要 Xcode，是否安装由用户决定；没有则继续写「未验证」。
