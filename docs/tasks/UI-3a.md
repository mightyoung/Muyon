# UI-3a 最小语义契约与可运行 Web 预览

## 目标、依赖与边界

首个编码切片：固定可校验的事实/显示/动作合同，以两组公共夹具渲染真实控件并可点击、编辑、返回；不能只交 JSON 校验器。依赖已合 UI-1a、REG-2、AUTH C2，不依赖训练、双模型选型或实机。只新增纯语义入口和预览，不把主宿主改成 Web。

## 现有复用与文件

复用 `packages/muyon_module_api/lib/src/references.dart` 的 ObjectRef/ArtifactRef 与现有 ontology 的宿主投影（不直接导入带tools/SQLite的ontology总类型）；UI 复用 `packages/muyon_ui/lib/src/catalog.dart` 的真实目录及 primitives/confirmation/theme。总入口 muyon_module_api.dart 传递导出 SQLite 类型，Web 不直接导入它。

拟新增：`packages/muyon_module_api/lib/ui_contract.dart`，`lib/src/ui/{snapshot,intent,plan,validation}.dart`；`apps/muyon_ui_preview/{pubspec.yaml,lib/main.dart,lib/preview_app.dart,lib/fixture_ports.dart,assets/fixtures/}` 与 Flutter 生成的 web 入口；`packages/muyon_module_api/test/ui_contract_test.dart`、预览 `test/preview_smoke_test.dart`。修改根 pubspec.yaml 注册 workspace 成员；不改 apps/muyon/main.dart/bootstrap、原迁移和授权发行接口。

## 接口决策

- DataSnapshot：snapshotId/revision、实际对象和字段、单位、verified/unverified/not_disclosed/not_applicable/read_failed/conflict、来源定位；UIPlan 只引用事实，不重新生成值。ObjectRef 的粗身份与 revisionRef 分开。
- InteractionIntent：purpose、requiredBindings、mandatoryStates、allowedActionRefs、snapshotRef。
- UiCatalog：version、真实 componentId/property schema/event schema 与可用动作。新增 Field/Table/SourceList 只能标为本批待实现适配，不能把 25 个未确认组件当现有目录。
- UiPlanningResult 联合输出：decision 为 textOnly/supplement/replacePresentation；后两者必须有完整 UIPlan，textOnly 不带 plan；reasonCode 表示展示理由。replacePresentation 只改变呈现，原完整问答继续保留。
- UIPlan：surfaceId/revision/catalogVersion/snapshotRef/intentRef/root/nodes；节点含稳定 nodeId、组件、绑定、children 与事件到动作引用。事件三路 local/business/semantic；选择组件或点击不是业务授权。
- BindingRef 区分 fact/uiState/computed/sourceSpan。uiState 只属界面/草稿；computed 绑定代码/领域已注册计算结果及输入版本，不接任意表达式；SourceSpanRef 复用 ArtifactRef 与内容摘要、页/段/范围，不能以模型复述替代上游原文。首片不建设通用计算语言或文档索引库。
- `UiValidationResult validateUiPlan(UIPlan plan, DataSnapshot snapshot, InteractionIntent intent, UiCatalog catalog)`；结果包含isValid/errors/validatedPlan；成功持有 ValidatedUiPlan，失败保留文字并给可见退路。UiEvent 有 eventId/surfaceId/nodeId/observedRevision/kind/payload。

动作绑定另有 inputRefs/expectedDraftRevision/operationKeyRef：payload引用必须解析到当前已校验草稿和冻结的确认记录集合；幂等键由host既有operation/decision产生，plan只能引用，不能自创字符串键。编辑版本变了，旧确认/payload失效；同次确认重复点击沿同一操作键。

父独审给出的25组件映射不等于当前全目录已动态实现；只选比较/试算最小集合。候选题题面若patch前后矛盾、t4引用或幂等规则不明，不作为有效预期；合同以实际生效版本和服务规则为准。

## 验收与测试

1. `unknown_binding_and_action_are_rejected`：不存在字段/动作、缺 mandatory conflict、错误 revision 均不进入渲染/业务调用。
2. `display_decision_union_is_consistent`：textOnly+plan、supplement 无 plan 被拒；正常补充计划保留完整文字。
3. `state_computation_and_original_span_remain_distinct`：qty=10、fixture 计算值=120 不被布局改写；本地编辑只变 uiState；原文段落引用解析到原字符串，源摘要变化显式失效。
4. `preview_click_edit_and_back`：390×844 和 1440×900 视口，展开来源、编辑 qty 到12、回到原卡仍保留本会话编辑；初始内存夹具不宣称重启持久。
5. 与现有真实组件逐项映射、按实际最小集构建，不预设全部新组件完成。uix-01比较试算、uix-02研究证据阅读、uix-03文件导入只能列为待审候选；来源审核前不是 gold 或成功样本。

新增 `current_after_patch_and_commit_refs_are_real`：base4→next5应用后下一规划current必须5；草稿rev15的提交引用到实际记录，编辑rev16后旧提交拒；重复同确认引用同操作键。测试片段（变量为本文件公共夹具）：

```dart
expect(validateUiPlan(unknownActionPlan, snapshot, intent, catalog).isValid, isFalse);
expect(validateUiPlan(validComparisonPlan, snapshot, intent, catalog).isValid, isTrue);
```

## 实施顺序

- [ ] 新建上述测试和虚构夹具，记录实际失败；测试只比较确定值、控件与事件，不以 sleep 控时序。
- [ ] 实现纯 Dart 模型、联合输出和校验；建立当前组件映射清单及明确缺口。
- [ ] 新建独立 Flutter Web preview，真实渲染并点击；仅公共/虚构数据，无宿主 bootstrap 或业务凭据。
- [ ] 运行 `flutter test packages/muyon_module_api/test/ui_contract_test.dart`；在预览目录运行 `flutter test`、`flutter build web --release`；实际浏览器点击截图。
- [ ] 交付可运行预览包与控件/事件证据。云 SDK 安装批准未到时不安装；可用已批准构建环境产生包交云浏览器验证，具体承载 URL 由 UI-4a 核查，不伪报部署成功。
- [ ] 独立审查后提交源码/测试及摘要；无效路径可关开关回到文字，旧业务页面不变。

## 通用门禁

本任务为待 leader 复核的派发草案，尚未开工；遵循[本批计划](../superpowers/plans/2026-10-08-ai-native-next-batch.md)。先运行新增行为回归取得有效失败，再最小实现、针对性复跑和独立审查；原始日志不提交，摘要进提交。云端 UI/业务流程验收通过并修复后可推进下一阶段；未覆盖能力登记待验收，原生及实机集中到 [R-1-AI-UI-final](R-1-AI-UI-final.md)，不逐片设实机前置。现有 Mac 截图例外只限已批准快照，不能自动沿用，见[备忘录](VERIFICATION-MEMO.md)。
