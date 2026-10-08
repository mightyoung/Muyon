# R-1-AI-UI-final 最终原生与实机验收清单

## 目标与依赖

并入现有 R-1 的末次验收，不重建取证器。云端各切片 UI/流程通过后可继续下一阶段；本清单集中补真实 Android/macOS/Windows与原生能力，不成为中间任务逐片门槛。依赖对应任务实现与云验收记录，模型真实效果按实际可用配置单列。

## 复用和证据

复用 `apps/muyon/integration_test/platform_device_test.dart`、north_star_inquiry/support、scripts/doctor.sh 与现有R-1流程；新增原生UI场景测试 `apps/muyon/integration_test/dynamic_workspace_device_test.dart`，证据摘要归任务审查，不提交原始运行日志。没有设备/凭据的项保持未验收。

## 最终待验项目

- [ ] 三端布局、大字号、键盘、触控与真实对象页返回；用户编辑、滚动/草稿现场保留。
- [ ] 真实SQLite迁移/重开、版本不兼容、旧快照与回执续办，历史业务数据保留。
- [ ] 文件选择/沙箱权限/MD HTML PDF预览及源码定位，实际Paddle OCR/平台桥/本地模型运行时；云模拟能力不得直接改为通过。
- [ ] 返回、换插件、锁屏、断网、进程终止分别测；系统限制时真实暂停，不承诺全平台后台常驻。
- [ ] 询价读写/导入有效集合实际入库、真实授权与outbound ledger、超时后查receipt不重复；设备通信依旧授权。
- [ ] 子对话关闭重开/引用最新、一层限制，两模式完整问答/目录/事件可用性；真实模型效果与夹具结果分列。
- [ ] 按VERIFICATION-MEMO重跑Mac完整Inquiry/verify，调查46既有golden根因；不更新golden/跳过/容差掩盖，例外不可自动延续到新SHA。

每项记录平台/硬件/OS/SDK/应用SHA/目录与模型版本、实际操作、领域结果、截图或录屏。E-1/原AC-01至30追踪“通过/失败/未测”，不以云端截图替代三端产品验收。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。

实际执行时先用 `flutter devices` 记录设备，再从 apps/muyon 运行 `flutter test integration_test/dynamic_workspace_device_test.dart -d <实际设备ID>`；新测试不存在前不执行、不冒称已跑。Mac完整门禁沿现行 `bash scripts/verify.sh`，模型/目录/输入版本和未覆盖项分别登记。
