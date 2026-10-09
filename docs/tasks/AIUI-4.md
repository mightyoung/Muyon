# AIUI-4 四导航外壳、工作区展示与返回恢复（任务书草案）

状态：**草案，待唯一集成审查**。用户已授权并行推进开发；可先实施旧dynamic基础外壳与恢复片，正式新契约未采纳的交互不得生产启用。执行分支建议 `task/aiui-4-conversation-shell`，执行者由唯一集成负责人派发。依据：[AI 原生界面方案](../design/ai-native-ui-redesign-2026-10-09.md) §4.1、§5.4、§5.5、§8；ADR-0001 用户决定、ADR-0002、ADR-0004、ADR-0005、HANDOVER-LEADER A～D及 REVIEW。实施前重新读取这些资料；缺技能检查 `.agents/skills`。

本草案代码基线为 develop `01404ae472451f55af5baa6ce76c95af72b0cbfc`。AIUI-2 最新参考 `4e45836efcb85c86f5c8de57e6b07795aab6166a` 含 Tabs 后续修复，但仍为未合分支；不得写成 develop 已有。原全库审计的冻结 SHA 和报告保持不变。开工先 fetch 三条相关分支并冻结完整 SHA，记录实际选择的组合与冲突；只有正式集成树通过才可宣称接线通过。

## 1. 交付行为与范围

打开应用默认进入**助手**。唯一主导航顺序为**助手、任务、资料、设置**：移动端底栏、桌面图标轨；四项标签、选中语义、键盘焦点行为一致。任务承接执行面板、待处理/确认事项、子对话入口及数据交换执行记录；资料承接对象/文件检索、原业务页面入口和工作区选择；设置承接现有模型、外观、数据去向、存储备份、插件配置入口。设备聊天、记忆、通知等已有入口应有明确的新归属和可达性测试，不得因删“我的/工作台”消失。不得把现有任务/设备状态误写为已成功的业务回执。

回答为主区。宽屏可在右侧打开一个“当前工作区”，同一时刻同一 task/surface 只持有一个有效 controller/router；手机以独立 route 展示同一工作区。资料和回答均可进入已有插件固定页面；固定页面是保留的兜底功能，内部业务逻辑冻结。禁止新增第五主导航，禁止重做 Folio/科研业务页面、对象工具或授权规则。

首次路由映射必须输出代码内可维护的四导航 destination 定义，避免不同断点各维护一份列表。采用项目现有 900 logical px 导航断点；桌面工作区仅在可容纳主区和侧栏时（初版沿用 1250 logical px）显示，否则使用移动 route；侧栏滚动独立且可关闭。200%文字时通过内容测量/布局退路避免固定宽度挤坏输入和确认内容。修改阈值需在任务回报说明实测依据。

## 2. 必须复用的现有边界

| 现有位置 | 本任务复用与允许修改 |
|---|---|
| `apps/muyon/lib/app/app_shell.dart` | 保留 MuyonApp 的 host生命周期、generation/recovery换树、theme与reduceMotion；仅传递外壳依赖/保存生命周期，不重写restore。WorkspacePage 继续打开原业务页面 |
| `apps/muyon/lib/screens/platform_shell.dart`及`platform_shell_home.dart`、`platform_shell_knowledge.dart`、`platform_shell_personal.dart` | 调整主导航和入口归属，复用 executionPanel/openModule/openSection/openObject、资料查询和设置；不得复制插件激活/对象解析 |
| `apps/muyon/lib/screens/assistant_page.dart` | 保留conversation、scope、draft与子对话服务；将直接push工作区入口抽成注入的宿主打开回调，未注入时保持旧route兜底。根助手切导航不能靠每次build新建conversation |
| `apps/muyon/lib/screens/dynamic_workspace.dart` | 复用 load/receipt/referenceLinks；把可嵌入正文与route chrome分开，确保desktop不出现双Scaffold/双返回；controller与router的owner明确且dispose一次 |
| `apps/muyon/lib/platform/ui_workspace_store.dart` | 原task/surface/scope隔离与SQLite CAS保持不变；不另建第二套业务草稿store |
| `apps/muyon/lib/platform/ui_navigation_anchors.dart`、`object_pages.dart` | 继续使用 NavigationAnchor、先flush后跳转、ObjectPages/ModuleSession、失效引用fallback及lease dispose；不得把anchor解码成模型提供的任意route |
| `packages/muyon_ui/lib/src/dynamic/workspace.dart`、`workspace_view.dart`与`muyon_module_api/lib/src/ui/workspace.dart` | 复用userOverrides/viewValues、revision、returnAnchor、nodeIds、scrollOffset、operationRefs；需改通用runtime时单独列接口diff并经唯一集成审查，不由shell分支扩展typed-state契约 |
| `apps/muyon/lib/platform/assistant_subconversations.dart`与`apps/muyon/lib/screens/assistant_subconversation_panel.dart` | 使用既有单层子对话/CAS协议；父子task/scope隔离、只读引用和人工草稿不得改为共享可写状态 |

可新增 `apps/muyon/lib/screens/conversation_shell_controller.dart` 管理shell展示选择/恢复与单controller所有权，`apps/muyon/lib/screens/conversation_workspace_pane.dart` 管理正文展示；实现者可合并小文件，但最终回报精确路径。不得将shell选择控制器做成模型动作执行器。

## 3. 返回、保存及刷新契约

必须区分四种信息：①既有workspace可持久化的人工字段/视图值；②返回定位（conversation/task/surface/node/object或artifact完整身份/digest、scroll）；③正在等待的业务operation与真实回执；④尚未完成模型流的内存draft。④按ADR-0005原边界，未完成流不能因本任务自动入库，更不能恢复为已定稿可点计划。

- root助手↔四导航切换：保留同一conversation的未发送人工输入、选中模型和对话scroll；不得触发send、启动模型或新建重复task。根页系统返回遵循平台退出语义，不造循环route；若有侧栏/嵌套route先关闭当前工作区或返回上层。明确测试返回栈长度和无自动send。
- 回答→工作区→真实对象/原文→返回：离开前await现有controller.flush；anchor包含完整身份且node存在于当前validated plan。返回后恢复人工值优先级、草稿修订、选中记录/步骤、滚动位置和node定位。scroll不得负值/非finite；布局变化后仅按真实extent clamp，不伪造node。对象revision/digest变化显示失效/变化信息，不能悄悄打开另一个对象或覆盖原草稿。
- 两个窗口/快速点击/导航与保存并发：同一projection采用原CAS；失败保留输入、显示“未保存/只读”，禁用业务动作，不能先pop再丢失错误。复用flush队列；不得用延时sleep掩盖冲突。shell选中项不成为workspace写入revision的替代来源。
- 切后台/窗口关闭：在可await的退出/route返回路径checkpoint；在平台不可await的detach处做既有尽力保存并明确失败边界，不能承诺强杀后最后一个未提交字符必恢复。测试模拟inactive/paused及关闭重开真实SQLite；另列真机强杀验证，日志不进仓库。
- 重新打开/宿主恢复换代：从真实store和当前host重新校验，不保留关闭host的listeners/controllers/object leases。未知schema/catalog/intent、scope变化、节点身份/绑定变化、旧snapshot逆序、损坏store/anchor走现有readOnly或可读fallback，保留原数据。scope不匹配不得迁移/扩大权限。
- snapshot刷新：保留userOverrides，不以新的extracted值静默覆盖；显示数据版本变化入口。计划更新保留合法稳定node/scroll/focus；节点变更不兼容时降为只读旧草稿，不靠新节点id重建后称“已恢复”。刷新不调用模型/业务写入。
- pendingreceipt：持久operationRefs在返回/重启后仅查询真实receipt；unknown保持unknown且锁定，不能重发同operation，不将按钮点击或模拟receipt显示成成功。异步回执回来的task/surface/host generation必须匹配，否则丢弃展示更新，保持审计记录。
- 子对话：复用既有单层panel。关闭/返回恢复父人工输入与scroll；父任务取消、子CAS冲突、插件失败都不丢待输入；子任务结果仅按既有只读引用回父，不自动扩大父授权。

## 4. 与AIUI-5、AIUI-8的接口与执行顺序

1. **AIUI-4a（shell owner）**：以develop旧dynamic-1+宿主固定fixture完成四导航、入口迁移、state ownership与route/pane展示；不等真实模型/新组件adapter，不宣称library-1可渲染。
2. **AIUI-4b（导航恢复 owner）**：在旧validated plan完成真实SQLite往返、CAS冲突、对象/原文返回、pending回执及生命周期测试。只接受宿主已经validated的plan，未合AIUI-2兼容性可在临时组合树独立核对。
3. **AIUI-5（planning/adapter owner）**向shell提供：宿主taskId/conversationId/surfaceId、已验证最终计划或纯文字/模板fallback、完整原回答、只读诊断和由宿主登记的event/business mappings；预览阶段不可点业务动作。AIUI-4只负责选择展示位置/返回，不定义组件codec、typed event、业务授权，也不处理模型自报route或identity。
4. **AIUI-4c（shell owner + AIUI-5交叉验收）**：adapter正式完成后，在冻结组合SHA运行回答→workspace→对象→返回及fallback正反fixture；未通过正式契约不得以启用开关放出新交互。
5. **AIUI-8 owner**负责“自动/少用/只用文字”、助手授权页和最终设置策略。本任务提供设置入口及注入展示策略接口，消费宿主已有策略；未有策略实现时保持当前安全行为，不能新增默认授权。只用文字时保留完整原回答和原页面入口/可读草稿，禁用新交互入口；不改变既有工具授权与操作恢复规则。AIUI-4测试注入策略fixture，不冒称AIUI-8已落地。

唯一集成审查按owner汇总接口与fixture；严禁shell/adapter各保存一份UIPlan或各持有router造成重复dispatch。跨owner接口变化先提供具体diff及测试证据，草案不能作为正式typed契约变更批准。

## 5. 必须实现的测试（路径、名字、断言）

下列新增名字是验收约定，不是既有通过证据。复用`apps/muyon/test/support/ui_navigation_fixture.dart`与现有真实SQLite/public fixture，fixture只用非业务敏感固定数据，假provider/receipt计数器；任何测试不得请求真实模型、读取用户业务目录或网络。

| 修改/新增测试文件 | 必须添加/维护test名 | 必须断言 |
|---|---|---|
| 修改 `apps/muyon/test/responsive_shell_test.dart` | `assistant_is_default_and_four_destinations_are_exact`；`four_destinations_320_390_430_900_1250_1280_at_200_percent` | 启动AssistantPage唯一主实例；仅四标签且顺序正确；phone NavigationBar/desktop Rail正确；轮流访问均可达；takeException=null，无溢出；不再断言旧“工作台/我的” |
| 新增 `apps/muyon/test/conversation_shell_navigation_test.dart` | `switching_destinations_keeps_unsent_parent_draft_and_scroll`；`root_back_closes_workspace_before_exit`；`data_and_answer_open_same_registered_business_page`；`legacy_entries_remain_reachable` | 实际enterText/scroll→切换→返回逐项等值；模型send/toolCalls=0；侧栏关闭后root栈未重复push；两入口ObjectRef一致且lease最终dispose一次；通知、设备聊天、记忆、数据交换等入口有唯一归属 |
| 新增 `apps/muyon/test/conversation_workspace_pane_test.dart` | `resize_moves_one_surface_without_duplicate_controller_or_dispatch`；`desktop_close_checkpoints_before_dispose` | 390→1280→390显示一个surface/router；人工值、node和pending锁不变；事件一次只dispatch一次；store成功前不能dispose/pop；失败留pane和输入 |
| 扩充 `apps/muyon/test/dynamic_workspace_return_test.dart` | 保留 `edited_value_survives_patch_reload_and_back on real SQLite`；新增 `shell_object_return_restores_manual_value_node_scroll_and_revision`；`snapshot_refresh_keeps_user_override_and_marks_version_change`；`paused_checkpoint_reopen_preserves_committed_projection` | 真正编辑、滚动、push实际对象页/pop，再关库重开；比较保存revision/userOverrides/nodeIds/anchor完整字段；新extracted不覆盖人工值；持久committed值恢复，未完成模型draft不被定稿 |
| 扩充 `apps/muyon/test/dynamic_object_navigation_test.dart` | 保留actual_object/stale_reference/unavailable_plugin用例；新增 `desktop_unavailable_plugin_return_keeps_parent_workspace`；`stale_anchor_does_not_open_another_object` | plugin失败仍可返回；object模块/类型/id/revision/digest不匹配拒绝；旧草稿和原回答可读；无新增业务绑定 |
| 扩充 `apps/muyon/test/ui_workspace_store_test.dart` | 保留CAS并发/scope隔离用例；新增 `shell_checkpoint_cas_conflict_does_not_pop_or_overwrite` | 两真实store以同expectedRevision写入只有一个成功；失败方人工输入仍显示，business port计数0，DB仍是胜者projection |
| 新增 `apps/muyon/test/conversation_shell_recovery_test.dart` | `pending_receipt_reload_queries_once_and_never_replays`；`unknown_receipt_remains_locked_and_not_success`；`host_generation_replaces_old_listeners_and_leases`；`corrupt_or_incompatible_workspace_is_readable_without_rewrite` | 持久operationRefs→重开仅receiptLookup；tool invocation计数不增加；unknown未显示成功；close/restore后旧host不收事件；损坏raw bytes不改写；错scope无草稿泄漏 |
| 扩充 `apps/muyon/test/assistant_subconversation_widget_test.dart` | 保留 `CAS conflict retains panel and pending input`；新增 `shell_child_back_restores_parent_draft_and_scroll` | 实际父输入→打开单层子→子关闭，父draft/scroll相等；子取消/CAS冲突保留输入，不自动send父消息/写工具 |
| 新增 `apps/muyon/test/conversation_shell_accessibility_test.dart` | `navigation_workspace_and_back_have_48_targets_and_selected_semantics`；`keyboard_focus_returns_to_source_node`；`text_only_keeps_answer_and_fixed_page_fallback_without_new_actions` | 每项目标宽/高≥48；标签/选中状态/返回语义正确；键盘Tab+激活往返焦点到有效源节点或明确fallback；200%模式下完整确认正文；注入text-only后完整文字与固定页面可达，新业务动作0 |

测试所有权：本任务独占修改 `apps/muyon/test/dynamic_workspace_return_test.dart` 和 `apps/muyon/test/ui_workspace_store_test.dart`；AIUI-5可只读复跑，并在其独立 `ui_bound_workspace_recovery_test.dart` 写新目录/typed/集合恢复专项。跨任务需要补现有文件时，由另一方交补丁给本owner顺序应用。F4b是上述旧dynamic恢复片；等待F5b/c的新版联调统一称F4c。

为避免只是测字段相等，返回恢复测试必须通过真实用户动作→实际导航→数据库reload路径；对象页使用真实注册插件的公共fixture，不用两页相同Text冒充对象页。若现有LiveTestWidgets绑定与新增测试不兼容，拆独立文件/CI进程，不能用sleep或跳过核心断言换通过。golden只用于外观，不能替代上述行为测试；新增可共享固定fixture且须标“模拟”。

## 6. 执行命令与完成证据

云端隔离工作树实施，避免占用用户Mac。按CI锁定Flutter/Dart版本，先记录SDK及SHA。最小测试从红到绿后跑受影响全量；未安装Flutter须明确未运行，交精确SHA CI，不得把静态脚本称widget通过。

```bash
cd apps/muyon
flutter analyze
flutter test test/responsive_shell_test.dart test/conversation_shell_navigation_test.dart test/conversation_workspace_pane_test.dart test/dynamic_workspace_return_test.dart test/dynamic_object_navigation_test.dart test/ui_workspace_store_test.dart test/conversation_shell_recovery_test.dart test/assistant_subconversation_widget_test.dart test/conversation_shell_accessibility_test.dart
flutter test
cd ../../packages/muyon_ui
flutter analyze
flutter test test/workspace_controller_test.dart test/workspace_view_test.dart test/dynamic_events_test.dart test/dynamic_surface_test.dart
flutter test
cd ../muyon_module_api
flutter analyze
flutter test
```

若新增文件尚未实施，上述命令不能列成已跑；最终交接逐文件报告实际test注册数、通过/失败/跳过/未运行，明确Golden平台跳过及真机未执行。原analyze/test/变异日志仅云工作区或CI artifact，摘要入任务回报，不进仓库。

必做两个针对行为的临时变异：①去掉导航前flush→`desktop_close_checkpoints_before_dispose`或CAS用例必须失败；②恢复时重发pendingoperation→`pending_receipt_reload_queries_once_and_never_replays`必须失败。变异结束还原并重新验证，不能削弱validator或已有拒绝断言。Android/iOS/desktop实机另外核对系统返回、后台/强杀边界、读屏/键盘、200%字号和48点击区；离线fixture不要求生产凭据。

完成回报：最终完整SHA、修改范围与接口diff、四导航入口映射、单controller/router所有权、真实返回/重启证据、CAS/pending/失效插件负例、两变异结果、CI链接及测试计数、尚未验证的实机事项。没有最终组合证据只能说“shell基础通过”，不能说“新组件/真实模型全链路接入完成”。执行者按已授权派发范围推任务分支，不合develop/main；当前文档交付只推独立文档分支。合入由唯一集成负责人依据REVIEW下结论。

## 分片执行检查表

- [ ] 先在导航/pane/真实SQLite返回专项写交付表中的行为RED，确认不是空断言或只检查fake调用。
- [ ] 实施四destination与同工作区route/pane展示，复用现有store/anchor/任务系统及唯一controller。
- [ ] 运行390→1280→390、真实对象返回、CAS冲突/pending回执/宿主generation与200%语义专项。
- [ ] 在AIUI-5采用新adapter后冻结组合SHA，运行回答→工作区→详情→返回与模板fallback；未就绪时只交旧dynamic基础片。
- [ ] 按共同门禁与两变异验证交分片SHA；设备与强杀证据单列，唯一集成负责人合入。
