# P0-3c 审查结论

审查对象：`task/p0-3c-chain-per-question` @ `8e752b7` · 审查：leader（代码核实由 Sonnet 子代理执行）· 日期：2026-10-06

**结论：通过，合入 `develop`。** 没有阻断项和应改项。

## 核实结果
- **范围**：只改了 `north_star_chain.dart`、新增的 `test/north_star_cross_tool_test.dart` 和运行手册，没有改动生产代码。
- **N1 逐题判定**：比价题必须有成功执行的 `inquiry.compare_quotes`，预算题必须有成功执行的 `inquiry.project_budget`。判定依据是 `receiptsBefore` 之后各题自己的回执。探针结果如下：

| 探针 | 结果 |
|---|---|
| 诚实模型 | 通过 |
| `cross_tools` | 失败，原因写明「compare_quotes 题没有用 inquiry.compare_quotes 作答」 |
| `unrelated_read_tool` | 失败 |
| `skip_tool_budget` | 失败 |
| `wrong_read_tool` | 失败 |

  变异测试：把逐题判定关掉后，新测试会失败，`cross_tools` 也会重新判为通过。这说明新测试确实守住了这项修复。
- **N3**：`MUYON_EVAL_REAL` 取 `true`、`yes`、`0` 时，只提示一次「只接受 1」，然后照常跑夹具，不会向端点发请求；取 `1` 时才走真实模型路径。
- **N4**：伪造写入时，`assistant.write.create_inquiry` 这一步为 `ok:false`。
- **运行手册**：第 123 行写明了逐题强制判定，人工核对那一步已去掉。
- **回归**：analyze 零问题；`dart format` 无改动；两个无头测试各跑 2 次都通过；`north_star_chain.dart` 590 行，没有超过 800 行的上限。

## 只记录（可选）
1. 只读题完全没调用工具，或者任务本身失败时，`failure` 里只有任务 id，没有题名和所缺的工具。不过步骤名（例如 `assistant.read.project_budget` 为 `ok:false`）已经能指明是哪道题。
2. 交叉工具测试的脚本里，预算题那一半其实执行不到，所以这个测试守不住 `receiptsBefore` 的回退。
3. **导出 `MUYON_EVAL_REAL=1` 时，交叉工具测试不再与外部隔离**：它会走真实模型路径，结果失败，或者真的发出请求。普通运行不受影响。P0-4 的说明里已经加了提醒：跑 `verify.sh` 时不要导出这个变量。以后可以让这个测试在 `realRequested` 为真时自行跳过。
4. `question!`、`requiredTool!` 的写法只是表面问题。
