# AIUI-2 组件库 v1

分支 `task/aiui-2-component-library` · 依据：[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §5.2、§5.5；[前端开发备忘录](../design/v6/frontend-memo.md)；UI-1a 的 `muyon_ui` 套件 · 执行：junior · 审查：leader A（交叉核实可派 engineer）

## 只做这些
1. **合并两份重复的目录**：`packages/muyon_ui/lib/src/dynamic/catalog.dart` 和 `dynamic_ui/catalog.dart` 合成一份，用到它们的地方改为引用新目录。行为不变，现有测试照常通过。
2. 按方案 §5.2 补齐组件，每个都要在目录里登记组件模式（属性、绑定、事件），并实现只读、加载、错误、降级四种状态：
   - 版式：Heading、Prose、Section、Columns、Tabs、Disclosure
   - 数据：KeyValue、Metric、CompareTable、Chart（柱、折线、饼，数据只能来自绑定）
   - 输入：Choice（单选、多选，可自填）、Form、NumberStepper、Slider、Toggle、DateField
   - 业务：SourceCard、FileCard、ProgressCard、Checklist、Timeline

   已有的 Table、ObjectChip、StatusBadge、ScopeChip、WarnBanner、ConfirmCard、BatchConfirmCard 保留，只补齐缺的状态。
3. 每个组件都要有：
   - 文字等价物：读屏朗读和复制时用；Chart 附带数据表；
   - 尺寸自适应：48 是最小点击区，200% 字号不溢出（UI 方案 §8 第 19 条）；
   - 在 debug 组件目录页里能用固定样例单独渲染；
   - widget 测试，测点击区、语义标签、200% 字号不溢出；golden 测试沿用 UI-1a 的约定。
4. 颜色只用 v6 token，不写死颜色。

## 不做
不接入助手和流式编译器（AIUI-1、AIUI-5）；不改页面；不新增第三方依赖。Chart 用 Flutter 自己画（`CustomPainter`），不引图表库；如果确实需要图表库，先回报，由 leader 决定。原始日志不进仓库。

## 验证
`flutter analyze`（`muyon_ui`、`apps/muyon`）；`muyon_ui` 全量测试；宿主全量 `flutter test`。变异：去掉某个组件的语义标签；把 Slider 的点击区改成 40。对应测试都必须失败。

## 回报
分支与提交哈希、组件清单（新增与补齐）、合并目录的改动点、验证摘要行、变异结果。
