# UI-2a 跨插件对象导航与文件预览返回

## 目标、依赖与边界

依赖 UI-3b/REG-4b；复用当前壳，以真实 ObjectRef/ArtifactRef穿透业务对象或文件，再返回原对话现场。不是全 UI-2/8/9 换壳；不另造路由或目录数据库。

## 文件与接口

复用 `platform/object_pages.dart` 的 `openModuleObjectPage(...)` 与 ObjectPages/ObjectPageLease、`app/app_shell.dart`、模块现有对象页。新增 `platform/ui_navigation_anchors.dart`、`screens/artifact_preview.dart`、host `test/dynamic_object_navigation_test.dart`/`artifact_preview_return_test.dart`。UiWorkspaceStore保存 `NavigationAnchor(conversationId,taskId,surfaceId,nodeId,scrollOffset,objectRef,sourceDigest)`；`Future<void> openReference(ObjectRef ref, NavigationAnchor returnTo)` 走既有 opener。

MD/HTML/PDF用实际可用阅读器或明确只读退路，不把PDF源码或模型重述当文件预览；内容摘要变化显示定位失效。设备聊天 chat_thread_page不是个人Agent会话库，不借它重建会话。

## 验收、测试与步骤

- [x] `open_actual_object_and_restore_workspace`、`unavailable_plugin_keeps_return_route`、`changed_source_marks_anchor_stale`先失败：打开真实研究/询价对象，返回编辑qty12与滚动锚点不变，lease释放一次；插件停用仍可回原对话。
- [x] 薄适配 existing opener，UI-3b锚点持久；预览浏览器用公开对象/文件样例，实际host ObjectPages云widget测试单列。
- [x] 运行新增两个文件、research_object_open/module_declared_ui 和 REG-4b 回归；本地公开预览移动/桌面 widget smoke 通过。
- [ ] cloud 浏览器移动/桌面导航 smoke（未部署，本次不代称通过）。
- [ ] 云UI/流程通过继续子对话；原生PDF平台差异、真实文件定位由末次清单验，不假称已通过。
- [x] 独立审查/提交；旧对象页和返回路径始终可用，失效引用不清空草稿。

## 通用门禁

本任务经 leader 授权实施；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。


## UI-2a 实施记录（2026-10-09）

在 develop 集成结果 `20c3088` 上建立独立 `task/ui-2a-reference-return`。

- 纯 UI 合约导出 NavigationAnchor，host 继续使用 UiWorkspaceStore 的 returnAnchor/scrollOffset，不另建目录或对话库。旧字符串 anchor 读取为无结构锚点，原草稿和原值仍保留。
- PlatformShell 的个人助手把已验证 UI plan 中的 ObjectRef/ArtifactRef 交给真实入口；checkpoint 复用任务、surface、conversation 归属及 CAS，返回保留 qty12 与滚动现场。
- 研究对象复用现有 opener；询价声明 ObjectPages，只将现有实际页面支持的 project/project_item/supplier/product/inquiry 设为 unbound。全局供应商不需要伪造工作区绑定，删除、归属、版本和 digest 仍由既有 owner 校验；lease 不关闭共享 owner。
- 文件预览只从 host 已注册 knowledge artifact 解析，不把 ID 当任意路径或 URL。复用 KnowledgePreview；Markdown 实际原文已验证，来源变化提示旧定位失效。其他插件或未注册文件提供明确只读退路。HTML 是现有文本阅读退路；原生 PDF 阅读器、HTML 实际文件及页内定位仍未验收。
- 公开预览仅含公开模拟对象和文件，明确标示模拟；复用同一 NavigationAnchor 格式，移动/桌面 widget 导航和 store 重建恢复通过，不引入 host 数据服务。
- TDD 获得缺少引用按钮、全局对象无法打开、旧 anchor 解码异常及错误项目归属可打开等有效行为 RED，再最小修复。目标 host 66 项通过，公开预览完整 13 项通过。独立只读审查未发现 Important/Critical。
- 未部署云 UI、未做实机验收；未改变预算、model caps、网页授权或默认 planning。剩余 cloud smoke 和原生文件定位进入末次验收清单。

原始 RED/GREEN 与完整门禁日志仅保存在 `/tmp/muspace-ui2a-evidence-20261009`，不提交。

最终 Mac 全量门禁：八包 analyze 无问题，doctor23通过；module_api38/UI253/prototype40/research216/supplier491（3skip）/host1227（3skip）/ui_preview13通过。Inquiry289通过、1skip、46截图失败；与集成20c3088同环境基线46案例相同、184PNG哈希全同，新增/删除/变化均为0。Mac门禁不是全绿，未修改golden、阈值或skip。
