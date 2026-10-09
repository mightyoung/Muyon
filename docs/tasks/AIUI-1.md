# AIUI-1 流式界面协议与增量编译器

分支 `task/aiui-1-streaming-compiler` · **验收依据：[AIUI 流式界面契约 v1](../design/aiui-stream-contract.md)**（2026-10-09 按评审意见补清 action 映射、预览与最终计划分离、树与 patch、绑定范围、中断与上限）· 上位：[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §5.1、§6 · 执行：Codex · 审查：leader A（安全相关，另开一个审查子代理）

## 只做这些
1. 按契约 §2 在 `muyon_module_api/lib/src/ui/` 实现行解析，按契约 §1 建立 `UiStreamSession`：元信息、根 id、快照、意图、目录都由宿主给定。
2. **重构 `validation.dart`**：把单节点规则（组件、属性、绑定、事件与动作）抽成可以单独调用的函数；`validateUiPlan` 改为调用它们。行为必须不变，现有测试原样通过。
3. 实现增量编译器 `UiStreamCompiler`，按契约 §3（树与 patch）、§4（候选计划、增量预览、最终计划）、§5（绑定范围）、§6（中断、重复与上限）实现。
4. 差分测试按契约 §4：对同一份原始候选计划（包括带坏节点的），流式结论必须与 `validateUiPlan` 一致。
5. 只做协议层，配夹具；不接模型，不接界面，不改 UI-4b 的规划接口。

## 不做
- 不实现公式（AIUI-3）；不支持删除、重排、换父（契约 §8 的 v2）；不改组件目录（AIUI-2）。
- 已有测试只允许因第 2 步的重构做机械调整，不得放宽断言。原始日志不进仓库，摘要写在提交说明里。

## 验证
- 契约 §7 的全部要求：每条规则都有拒绝路径的测试；四个变异各自由指定的测试检出；差分测试。
- `flutter analyze`（`muyon_module_api`，info 也算失败）；`muyon_module_api` 全量测试；宿主全量 `flutter test`。

## 回报
分支与提交哈希、新增文件、单节点规则的抽取方式、契约逐条对应的测试名、验证摘要行、变异结果。
