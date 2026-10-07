# 设计稿 v5（目标稿）

来源：Claude Design 第五、六轮产出（按 [v4 第五轮](../v4/prompts/claude-design-prompt-round5.md)、[第六轮](../v4/prompts/claude-design-prompt-round6.md)提示词）。用户 2026-10-07 放在本机 `docs/design/claude-design/v5/`，原样入库，稿件内容没有改动。

- **地位**：已被 [v6](../v6/README.md) 取代（第七轮修正后）。原为取代 v4 的目标稿。与 [UI 重设计方案](../ui-redesign-brief-2026-10-06.md) §8 冲突时，以方案为准。
- **审阅**：[2026-10-07-design-v5-review.md](../../reviews/2026-10-07-design-v5-review.md)。
- **返工**：[prompts/claude-design-prompt-round7.md](prompts/claude-design-prompt-round7.md)（收尾修正，不加功能）。第二至第六轮提示词在 `../v4/prompts/`。
- **规格**：[tokens.md](tokens.md)、[components.md](components.md)。当前状态以 `round6-notes.md` 为准。
- 附件 `uploads/` 里的 `DESIGN.md` 和第二至第六轮提示词，都与仓库中已有的文件逐字相同，没有重复入库。

## 查看方式

用浏览器直接打开 `*.dc.html`，需要能访问 `unpkg.com` 和 Google Fonts。`support.js` 与 v4 的相同，具体说明见 [v4 README](../v4/README.md)。

## 相对 v4 新增或大改

| 文件 | 内容 |
|---|---|
| `Muyon Assistant Auth`（新） | 对话页的工具卡、确认卡（9 种状态、四类操作、「更多」里的授权范围）、批量确认卡、外部内容提示条、流式输出与停止、压缩提示；助手权限页（模式、四类开关、授权列表、变更审计、外传内容审查） |
| `Muyon Assistant Runtime`（新） | 执行记录（预算、已达上限、从断点继续、压缩确认框、事件时间线）、模型设置（预设、测试连接、流式开关）、数据去向（按通道筛选）、插件「助手能力」、敏感属性遮盖 |
| `Muyon Inquiry Home` | 删除 AI 任务、助手历史回答，改为概览加「问助手」入口 |
| `tokens.md` | 新增 `warn` / `warnbg`（规则段尚未统一，见第七轮 A） |
| 其余文件 | 工具 ID 换成真实名称，私有的 `amb` 改为 `warn` |
