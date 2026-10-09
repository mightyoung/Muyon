# AIUI-1 流式界面协议与增量编译器

分支 `task/aiui-1-streaming-compiler` · 依据：[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §5.1、§6；现有 `packages/muyon_module_api/lib/src/ui/`（`plan.dart`、`validation.dart`、`snapshot.dart`）· 执行：Codex · 审查：leader A（安全相关，另开一个审查子代理）

## 只做这些
1. 在 `muyon_module_api/lib/src/ui/` 新增流式协议：每行一个 JSON 操作，`op` 取 `text` / `node` / `patch` / `action` / `end`（字段见方案 §5.1）。定义解析结果的类型；未知 `op`、坏行、超长行都是可报告的错误，不能抛到调用方之外。
2. **增量编译器** `UiStreamCompiler`：逐行输入，输出「当前可渲染的计划」和每个节点的状态（`rendered` / `placeholder(reason)` / `pending`）。
   - 每个节点按 `UiCatalog` 里的组件模式**单独校验**；复用 `validation.dart` 已有的规则，不另写一套；
   - 绑定只能引用 `DataSnapshot` 里已有的事实或登记过的公式；动作只能引用目录里登记过的动作；
   - 不合法的节点换成占位并记录原因，不影响其他节点；
   - 父节点不存在、`id` 重复、`patch` 指向不存在的节点，都按不合法处理；
   - 流在 `end` 之前中断：已渲染的部分保留，整体标「未完成」，**半截的 `action` 一律不生效**。
3. `end` 之后得到的最终计划，必须与把同样内容一次性交给现有校验器的结果一致。用差分测试证明这一点。
4. 设上限：节点数、深度、单行长度、文字总长；超限时停止接收并标「未完成」。
5. 只做协议层，配夹具测试；不接模型，不接界面，不改现有的规划接口（UI-4b harness）。

## 不做
不改组件目录（AIUI-2）；不接入助手；不改已有测试。原始日志不进仓库，摘要写在提交说明里。

## 验证
- 变异（每个都要让对应测试失败）：
  - (a) 跳过逐节点校验；
  - (b) 允许绑定不存在的事实；
  - (c) 中断时让半截的 `action` 生效；
  - (d) 去掉节点数上限。
- `flutter analyze`（`muyon_module_api`，info 也算失败）；`muyon_module_api` 全量测试；宿主全量 `flutter test`。

## 回报
分支与提交哈希、新增文件、协议字段表、差分测试说明、验证摘要行、变异结果。
