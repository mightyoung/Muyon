# 设计稿 v6（目标稿）

> **2026-10-09：页面结构与导航已作废**，以 [AI 原生界面方案](../ai-native-ui-redesign-2026-10-09.md) 为准：以对话为中心，底栏 4 项（助手 · 任务 · 资料 · 设置），插件页面冻结为固定入口。本稿只保留视觉层（token、组件外观、深浅色）；[前端开发备忘录](../v6/frontend-memo.md)仍然有效。不要按本稿的导航和页面布局施工。

来源：Claude Design 第七轮产出（按 [第七轮提示词](../v5/prompts/claude-design-prompt-round7.md)）。用户 2026-10-07 放在本机 `docs/design/claude-design/v6/`，原样入库，稿件内容没有改动。

- **地位**：取代 [v5](../v5/README.md)，是 UI 重做的**最终设计参考**。稿内的错误以[前端开发备忘录](frontend-memo.md)为准。UI-1（设计系统）以本目录的 [tokens.md](tokens.md)、[components.md](components.md) 为准。与 [UI 重设计方案](../ui-redesign-brief-2026-10-06.md) §8 冲突时，以方案为准。
- **当前状态**：见 [round7-notes.md](round7-notes.md)。第七轮 A～E 都已处理；F2（320 宽、200% 字号、逐页检查浅色和深色）没有做。
- **审阅**：[2026-10-07-design-v6-review.md](../../reviews/2026-10-07-design-v6-review.md)。**设计稿到 v6 为止**（用户 2026-10-07），不再返工；遗留问题见[前端开发备忘录](frontend-memo.md)，开发时按它实现。
- **对比度**：`warn` 的实测值经 leader 用 WCAG 公式复算一致：浅色 `warn/sf` 5.93、`warn/warnbg` 5.31；深色分别为 10.97、8.60。
- 附件 `uploads/` 里的 `DESIGN.md` 和第二至第七轮提示词，都与仓库中已有的文件逐字相同，没有重复入库。

## 相对 v5 的变化

| 文件 | 变化 |
|---|---|
| `Muyon Dark Evidence`（新） | 深色模式下「选中行」「待确认」和 `warn` 警告条同屏，标注了对比度 |
| `Muyon Assistant Auth` | 外部内容开启时，外传授权也显示暂停；新增「已授权端点」外传卡；外部内容下批量卡不再有「全部允许」 |
| `Muyon Assistant Runtime` | 时间线分开「手动确认」和「由授权放行」两种示例；询价的可用操作里删掉 `transfer.send` |
| `Muyon Mobile` / `Muyon Desktop` | 补上写入确认卡、批量确认卡，以及外部内容开启时的变体 |
| 询价各稿 | 其余页面补上「问助手」入口；原型卡片显示「不适用」 |
| 全部 `.dc.html` | `height:44px` 一律改为 48。纯视觉元素可能被误改，需要渲染检查 |
| `tokens.md` / `components.md` | 规则统一为一种说法；警告条用 `warn`；删除 `info` 色调 |
