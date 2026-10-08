# UI-4a 确定性动态渲染与受控云端预览

## 目标、依赖与边界

依赖 UI-3a，REG-4a 提供实际能力目录用于业务联调。共享 Flutter 运行时渲染条件编辑、比较、来源和回执四类组合；设计复核后先在云端验收可操作流程。云端使用公共夹具，不能把浏览器预览变成完整主应用 Web 移植或新增生产微服务。

## 文件与复用

新增 `packages/muyon_ui/lib/src/dynamic/{catalog,surface,patch}.dart`，纯入口 `packages/muyon_ui/lib/dynamic_ui.dart`，测试 `test/dynamic_surface_test.dart`；UI-3a 预览复用同一个运行时。新增 `scripts/ui_preview/{smoke.mjs,README.md}`、`.github/workflows/ui-preview.yml`，预览夹具/集成测试；修改 `packages/muyon_ui/pubspec.yaml` 接纯合同依赖；现有 catalog.dart 是组件展示目录，不冒称生成式协议已有。

## 接口与验收

- `Widget renderUiPlan(ValidatedUiPlan plan, {required UiEventSink onEvent})`，UiEventSink 为 `Future<void> Function(UiEvent)`；只接 UI-3a 的校验结果。
- 定义 UiPatch(patchId,surfaceId,baseRevision,nextRevision,ops,snapshotRevision)；`UiValidationResult applyUiPatch(ValidatedUiPlan current, UiPatch patch, DataSnapshot snapshot, InteractionIntent intent, UiCatalog catalog)`。重复 ID 去重、乱序基础版本不符拒绝，完整消息形成后原子应用。Patch不能改写业务快照；需要新事实时由真实服务发布新DataSnapshot，再校验相应计划。
- local 展开/排序/草稿编辑不调用模型；business 交现有执行端口；semantic 交 UI-4b。业务结果只能来自真实/明确标识的模拟回执，不能由 plan 改 status。
- 先映射 PageScaffold、MasterDetail、StatusBadge、ObjectChip、ScopeChip、ConfirmCard/BatchConfirmCard、WarnBanner、SegmentedPill 等真实组件；缺失的 Table/Field/SourceList 做最小适配，不重做 v6。
- `partial_duplicate_and_stale_patch`：半条补丁不生效、重复不加两次、旧 revision 保留当前输入。`local_events_do_not_call_planner`：展开/排序后控件已变且规划调用为0。`mandatory_unknown_survives_fallback`：无效组件降级字段/来源/文字而不隐藏 unknown。
- 云浏览器真实交互：390×844、1440×900、大字号、浅/深色；编辑、比较、展开来源、确认/取消、页面返回，验证控件结果并截图。截图是观察证据，不能替代点击与状态断言。

`patched_current_is_used_by_next_planning`：实际应用base4→next5后，自动/显式重规划均读取current5，不从原始题面把旧t2版本重放替换成预期。父报告的候选题矛盾先登记修正，不双重接受相互矛盾的版本。

## 云门禁与模拟边界

云线程已核 Chromium151、Playwright1.62.1、Node24.19 可用；合成页面点击截图成功，不代表 Flutter 预览已通过。云无 Flutter/Dart，官方 SDK 安装仍等批准，不能自行安装。定位实际承载和受控访问 URL 后，用 `node scripts/ui_preview/smoke.mjs --base-url "$PREVIEW_URL"` 验证真实部署包。无部署能力就交可构建包/明确阻塞，不虚构 URL。

浏览器使用内存公共业务数据、模拟 ActionPort；模拟按钮/回执显式标识。云 CI 同时运行真实现有宿主/SQLite 夹具测试验证相同业务输入及回执，二者分别记证据，不宣称浏览器已调用原生数据库。OCR、原生文件权限、平台桥、设备传输列待最终原生验收。新增预览不能嵌业务密钥或上传真实业务资料。

## 实施顺序

- [ ] 先以乱序/半条/重复 Patch、大字号编辑和返回测试取得有效失败。
- [ ] 实现最小目录映射与稳定 nodeId 更新，接三路事件端口和标准布局降级。
- [ ] 完成 Web 编译兼容清单，复用 UI-3a 包；核实际云承载权限与工具路径，等批准的 SDK/构建方式。
- [ ] `flutter test packages/muyon_ui/test/dynamic_surface_test.dart`、预览 `flutter build web --release`；云 URL 上运行 smoke 脚本并保存移动/桌面交互与截图。
- [ ] 云测试报错先修复，云 UI/流程门禁通过可继续下一任务；未覆盖原生能力不写通过，也不作为每片实机门槛。
- [ ] 交审并记录版本、包摘要、实际 URL、视口/浏览器和覆盖矩阵；feature flag 关闭时回旧页面/文字。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
