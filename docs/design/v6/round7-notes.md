# 第七轮说明（当前真实状态）

## A tokens
- A1 已改：red/redbg 用途为失败、危险、外传。
- A2 已改：warn/warnbg 并入颜色表，旧「警告色」节已删。
- A3 已改：规则改为六条单一说法。
- A4 已改：对比度表为实测，工具为项目内 JS 脚本（WCAG 2.x 相对亮度公式）。warn/sf 浅 5.93、深 10.97；warn/warnbg 浅 5.31、深 8.60；其余配对见 tokens.md。
- A5 已改：新增 `Muyon Dark Evidence.dc.html`，深色下「选中行」「待确认」与「warn 警告条」同屏，并标注 8.60 / 8.47 实测对比度；区分靠色相、warning 图标与中文。

## B components
- B1 已改：警告条变体为 warn / 红 / tint。
- B2 已改：徽标色调只用 success / danger / warn / neutral，`info` 已删除。
- B3 已改：`round6-notes.md` 末句已更新。

## C 授权语义（Muyon Assistant Auth）
- C1 已改：外部内容开启时 transfer.send 授权也显示「本任务中暂停」。
- C2 已改：新增「外传 · 已授权端点」卡，按钮为 仅发送这一次 / 本次对话允许 / 拒绝，无「始终允许」；「新端点」卡保留。
- C3 已改：外部内容开启时批量卡无「全部允许」，顶部带提示条。

## D 执行记录（Muyon Assistant Runtime）
- D1 已改：手动确认示例的「执行」不再标由授权放行；新增「授权放行」时间线（无确认事件，执行标「由授权放行 · 查看授权」）。
- D2 已改：询价「可用操作」已删除 transfer.send。

## E
- E1 已改：Mobile、Desktop 对话页有写入卡（带「更多」）、批量卡，另加「外部内容开启时」变体（顶部提示条、无「全部允许」），与 Muyon Assistant Auth 同一结构。
- E2 已改：询价单、项目、技术要求、供应商、物料页已有「问助手」。
- E3 已改：Mobile 数据中心列表的原型卡片显示「不适用」（对象类型、关系、动作、流程）；插件注册页的四格同为「不适用」。
- E4 已核对：脚本扫描除文件名含「+」的两份外的全部 .dc.html，所有「外传」标签均配 redbg/red，「写入」均配 tint/deep，未发现例外。`Muyon Exchange+System`、`Muyon Inquiry Spec+Catalog` 因文件名含「+」脚本无法读取，未扫描。

## F
- F1 已改：全部 .dc.html（含两份含「+」的）中 `height:44px` 一律改为 48px，共 17 个文件；纯视觉的 44 高块（如图标）若被误改，需在渲染检查时再看。
- F2 未改：预览窗口宽度固定，无法切到 320 宽或 200% 字号；本轮只在 `Muyon Assistant Auth` 看过深色一屏。其余页面的浅深色逐页检查未做。
