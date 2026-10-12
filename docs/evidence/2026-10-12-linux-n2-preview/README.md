# Linux N2 删除影响预览验证（第二路，固定候选 da5b482）

- 候选 SHA：`da5b482619fde2dbaca0c84603135b1b81e94f13`（feat(research): preview section deletion impact without writes）
- 分支：`task/linux-n2-preview-validation`（仅新增测试与证据；未改生产代码和已有测试；未合入 develop/main）
- 环境：见 `env.txt`。Debian 13，X11 `DISPLAY=:4`，Flutter 3.47.5 / Dart 3.13.4。

## 结论：桌面交互受限，未做桌面交互验证

Linux 桌面构建不可行：缺 clang++、cmake、ninja、pkg-config、GTK3 开发头文件（按要求未安装系统依赖），
且 `apps/muyon` 没有 `linux/` 平台目录。因此**本轮没有启动桌面应用，不能称为桌面交互通过**。
以下全部是 flutter_test 下的 widget/semantics 检查（键盘相关用 `TargetPlatform.linux`），截图由测试内渲染生成
（系统 Noto Sans CJK 字体），只含合成数据，不含用户路径。

## 合成科研项目

项目 `p`（另有 `q` 作为外部项目）：
- 普通关联章节：1 条正常关联
- 混合关联章节：12 条正常关联 + 跨项目关联 + 证据实体缺失 + evidence_id 为空（共 15 条）
- 长标题章节：约 400 字标题 + 1 条关联
- 临时目录：`Directory.systemTemp.createTempSync('linux-n2-preview-')`，内存 SQLite，全部迁移

## 命令与退出码（在 packages/research_module 下）

| 命令 | 退出码 | 结果 |
|---|---|---|
| `flutter pub get --enforce-lockfile`（仓库根） | 0 | 顺带改写 3 个 analysis_options.yaml，已还原，未提交 |
| `flutter test test/section_delete_preview_test.dart test/section_delete_preview_ui_test.dart` | 0 | 20/20 通过（已有测试，未改） |
| `dart analyze test/linux_n2_preview_validation_test.dart` | 0 | 无问题 |
| `flutter analyze` | 0 | 无问题 |
| `flutter test test/linux_n2_preview_validation_test.dart -r expanded` | 0 | 26/26 通过 |
| `N2_EVIDENCE_DIR=<tmp> FLUTTER_ROOT=<flutter-sdk> flutter test test/linux_n2_preview_validation_test.dart` | 0 | 26/26 通过，生成 screenshots/ |
| `flutter test`（research_module 全包） | 0 | 302 通过 |

## 已验证（widget 层）

- 完整数量：混合章节显示“将移除 15 条证据关联”，12 条正常关联全部在列表中
- 证据保留说明“证据实体本身会保留”、“只读预览，不是删除确认”始终显示
- 跨项目 / 证据缺失 / 空 evidence_id 的关联显示“受限关联：详情不可读取”，不出现其 link/evidence ID
- 改合成数据后 ≤1.1s 出现“预览已过期，请刷新；不能用于删除确认”；旧数字保留；刷新后数字更新、提示消失；刷新后再次改动仍可检测
- 只删证据实体（删除摘要不变）也会因状态变化判为过期
- 对话框只有“刷新预览”“关闭”两个按钮，无删除/确认按钮；打开、刷新、关闭后全部业务表不变；真正删除仍需页面上单独的“删除段落”确认框
- 5 种窗口尺寸 × 1.0/2.0 字号：无溢出异常，两个按钮可点击，列表可滚动到最后一条
- 键盘：Tab/Shift+Tab 在对话框内的两个按钮间循环；Enter 触发刷新；Esc 关闭；数据不变
- 语义：两个按钮为可聚焦、可点的 button；标题、说明、数量、受限行都有语义标签；不暴露受限 ID
- 错误文案：outline 表损坏、作用域外项目、超预算时，只显示“无法生成完整预览：超出预算或无权读取”，不含 SQL 错误、表名、临时路径或 ID；诊断走 FlutterError 日志

## 发现（测试名带 FINDING，按观察到的行为固定）

1. 键盘无法滚动影响列表（中）。最小步骤：800x600、2.0 字号打开混合章节预览 → Tab 聚焦按钮 → PageDown/↓/End/Space，列表偏移均为 0（最大 1732）；鼠标滚轮可滚动（300）。纯键盘用户看不到首屏以外的关联。
2. 小窗口 + 200% 字号时单条关联比可视区还高（低）。320x480：单条 280px，可视区 136px；480x360：200px / 128px。能滚动但很难阅读。
3. “过期”提示不是 live region，样式与正文相同（低）。读屏不会播报；截图 05 中视觉上也不突出。
4. 章节在别处被删除后点刷新，显示“超出预算或无权读取”（低，文案）。原因不是预算或权限，用户可能误解。
5. 证据缺失与权限受限用同一文案（低）。UI 未传 `canReadEvidence`，“受限”只会来自跨项目、证据缺失、空 ID；核心层的 `canReadEvidence` 拒绝在 UI 中走不到（已在核心层测试 ID 被隐藏）。
6. 对话框路由语义名是通用的 “Alert”（测试环境未加载中文本地化），不是标题“删除章节影响预览”（观察项）。

另（不在 N2 代码内，仅代码阅读）：`apps/muyon/lib/main.dart` 启动失败时显示 `无法打开 Muyon\n$error`，原始异常可能带数据目录路径。

## 未测项

- 真实 Linux 桌面窗口：启动、窗口拖拽缩放、系统字体缩放、真实键盘/鼠标、AT-SPI/Orca 读屏
- `MUYON_DATA_DIR` 隔离目录下的整机启动（没有 linux runner，无法构建）
- 真实字体下的精确排版（widget 测试布局数字基于测试字体，截图用 Noto CJK 重新渲染）
- 刷新计时器在大数据量（接近 500 条）下的性能
- PR60 的数据库变异集（按要求不重复）；Android、真实模型、历史迁移、部署
