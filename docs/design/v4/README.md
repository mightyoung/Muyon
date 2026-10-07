# 设计稿 v4（目标稿）

来源：Claude Design 第二至第四轮产出，用户 2026-10-07 上传（`v4.zip`），原样入库，未改动稿件内容。

- **地位**：第一阶段之后 UI 重做的目标稿。与 [UI 重设计方案](../ui-redesign-brief-2026-10-06.md) 冲突时，以方案的「2026-10-07 修订」与 §8 为准。
- **审阅**：[2026-10-07-design-v4-review.md](../../reviews/2026-10-07-design-v4-review.md)（用户决定、稿内问题、与代码对照）。
- **返工**：[prompts/claude-design-prompt-round5.md](prompts/claude-design-prompt-round5.md)。前几轮提示词也在 `prompts/`。
- **规格**：[tokens.md](tokens.md)、[components.md](components.md)；每轮说明见 `round2-notes.md`～`round4-notes.md`（以 `round4-notes.md` 为当前状态）。
- 附件中的 `DESIGN.md` 与 [`docs/design/DESIGN.md`](../DESIGN.md) 逐字相同，未重复入库。

## 查看方式

用浏览器直接打开 `*.dc.html`。`support.js` 会从 `unpkg.com` 加载 React 18.3.1、ReactDOM 18.3.1 与 `@babel/standalone` 7.29.0（带 SRI 校验），字体来自 Google Fonts，所以需要能访问这两处。每个文件左侧是“可进入的二级页”和状态切换芯片。

| 文件 | 内容 |
|---|---|
| `Muyon Mobile` / `Muyon Desktop` | 壳层：底栏 5 项；桌面图标轨 + 二级栏 + 内容区 + 助手栏、⌘K、收件箱抽屉、平板竖屏 |
| `Muyon Accessibility` | 320/390/430 宽、200% 字号、tooltip、减少动态效果、对比度 |
| `Muyon Assistant Settings` | 助手设置：SOUL、规则配置、助手权限、记忆、模型 |
| `Muyon Data Center` / `Muyon Desktop Data Center` | 数据中心：本体图、对象类型、关系、动作、查询接口、流程、血缘、数据质量、AI 知识、AI 接入、实例浏览器 |
| `Muyon Inquiry Home` / `Core` / `Spec+Catalog` | 询价（手机）：概览、AI 任务、报价、比价、定标、询价单、项目、预算、技术要求、供应商、物料 |
| `Muyon Desktop Inquiry` / `Spec` / `Data` | 询价（桌面） |
| `Muyon Exchange+System` / `Muyon Exchange Hub` | 数据交换、配对、来件核验、数据包；存储备份、接口与 MCP；同步与交换、修改冲突、公司资料 |
| `Muyon Research` | 科研：概览、文库与阅读器、任务、结果、写作、研究关系图 |
| `Muyon Prototype` | 原型外围：列表、版本评审、反馈、导入、受限 WebView 外框 |
| `Muyon Platform Gaps` | 工作区、研究包导入、离线工具、执行记录详情 |
