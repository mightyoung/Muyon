# PR61 窄屏设置布局补修

固定源测试 `2a3201b8e920f61578dbf76019726437436380f3`，基线 develop `1a0131866ab33d87462ca49b3e4d75264b55e36a`。独立分支摘入源唯一文件 `apps/muyon/test/linux_host_settings_validation_test.dart`，其 blob 固定 `7e08c89b866fb68363ead4e660fc1d6153880698`，原断言、帮手和原作者分支均未改变。

独立实际原 RED：1 通过、3 widget 行为失败、0 跳过、自然 exit 1；390px 的 100%/200% 分别横向溢出 110/558px，1280px/200% 正常。新专属回归 RED `ff60fc6ff34bed69d8848e655918dd065238c26e`：10 通过、8 widget 溢出失败、0 跳过，均有 done(success:false)，不是 loader/编译/清理超时证据。

实际文件是 `apps/muyon/lib/screens/assistant_page.dart`，不是不存在的 lib/assistant/assistant_page.dart。Column 已给有限宽度，但 DropdownButton<UiPlanningMode> 默认内部 Row 按长标题自然宽度布局；默认固定 48px itemHeight 在文本变大后又会裁掉换行文字。产品仅两行修复：isExpanded:true 把文本约束到剩余宽度；itemHeight:null 让按钮与菜单项随完整文字增高。保持两条原完整长标题、两种规划选项和原回调，不减字体、不省略、不隐藏功能，也不改变三档偏好或权限闸门。

自己的 `linux_ui_planning_mode_layout_test.dart` 覆盖三档 automatic/few/textOnly × 320/390/1280px × 100%/200% 共 18 例。实际打开三档菜单检查三选项可点；auto/few 再实际选择两种 UiPlanningMode，确认 agent 值变化、完整末字 glyph 在按钮与其可视滚动 viewport 的交集中（排除文字省略和横纵裁切）。textOnly 保持原规划资格关闭，三档偏好菜单仍可达。每例均确认没有授权规则与工具调用；未调用模型。

实际 GREEN：原 PR61 4 例 + 自己 18 例 = 22 通过、0 失败、0 跳过，原先被首条错误挡住的偏好三次切换/真实存储重启断言现在全部执行。设置/主题/导航/呈现偏好九文件相关回归 60 通过、0 失败、0 跳过（不是整个宿主全量）。strict apps/muyon analyze 为 No issues found。补强可视 viewport 裁切断言后，又实际重跑这 22 目标全通过。

两个独立逆变异真实检出：去掉 isExpanded→11 widget 横向溢出失败；恢复固定 itemHeight48→4 widget 末字纵向超界失败（例如期望末字 bottom≤259.2，实际383.8）。均自然 exit1、done(success:false)，无 loader/timeout。产品文件恢复后的 SHA256 `7ba5d8eefe21f595c133ba2cbc19b5d21cdcd63156626204d7dc30d9a98889e3`；恢复后 22 目标全通过。

本报告是 Flutter headless widget + 真临时 SQLite fixture 证据，不是 Linux 桌面二进制启动或真人交互。没有安装系统依赖/工具链、运行模型、Android、部署或改变 MUYON_EVAL_REAL。N2 core 固定351、外部保留的 N2 preview UI 与其测试均未动。

原始 JSONL/analyze/变异日志在 `/workspace/reports/linux-settings-narrow-fix-20261012`，不入仓库。固定修复提交的源 CI、非作者独立复审及 root 最新 develop 组合门禁仍分别核终态；不以以上本地通过代替它们。本分支不合 develop/main、不强推或删除作者分支。
