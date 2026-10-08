# UI-2a 跨插件对象导航与文件预览返回

## 目标、依赖与边界

依赖 UI-3b/REG-4b；复用当前壳，以真实 ObjectRef/ArtifactRef穿透业务对象或文件，再返回原对话现场。不是全 UI-2/8/9 换壳；不另造路由或目录数据库。

## 文件与接口

复用 `platform/object_pages.dart` 的 `openModuleObjectPage(...)` 与 ObjectPages/ObjectPageLease、`app/app_shell.dart`、模块现有对象页。新增 `platform/ui_navigation_anchors.dart`、`screens/artifact_preview.dart`、host `test/dynamic_object_navigation_test.dart`/`artifact_preview_return_test.dart`。UiWorkspaceStore保存 `NavigationAnchor(conversationId,taskId,surfaceId,nodeId,scrollOffset,objectRef,sourceDigest)`；`Future<void> openReference(ObjectRef ref, NavigationAnchor returnTo)` 走既有 opener。

MD/HTML/PDF用实际可用阅读器或明确只读退路，不把PDF源码或模型重述当文件预览；内容摘要变化显示定位失效。设备聊天 chat_thread_page不是个人Agent会话库，不借它重建会话。

## 验收、测试与步骤

- [ ] `open_actual_object_and_restore_workspace`、`unavailable_plugin_keeps_return_route`、`changed_source_marks_anchor_stale`先失败：打开真实研究/询价对象，返回编辑qty12与滚动锚点不变，lease释放一次；插件停用仍可回原对话。
- [ ] 薄适配 existing opener，UI-3b锚点持久；预览浏览器用公开对象/文件样例，实际host ObjectPages云widget测试单列。
- [ ] 运行新增两个文件、research_object_open/module_declared_ui回归，以及cloud移动/桌面导航 smoke。
- [ ] 云UI/流程通过继续子对话；原生PDF平台差异、真实文件定位由末次清单验，不假称已通过。
- [ ] 独立审查/提交；旧对象页和返回路径始终可用，失效引用不清空草稿。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
