# SN-1 动态界面的确认卡接上「外部内容」标记（不变量 3）

分支 `task/sn-1-dynamic-confirm-external-content` · 基线 develop `a68ba43` · 执行：**Claude Sonnet 5.5** · 审查：leader A（安全路径，审查会做变异）

## 问题
[AI 原生方案](../design/ai-native-ui-redesign-2026-10-09.md) §6 不变量 3：外部内容进入任务后，回答里不出现放行类按钮（ADR-0002、ADR-0004 Q11）。GROK-8 追溯发现：
- `packages/muyon_ui/lib/src/dynamic/surface.dart` 约 871 行渲染动态 `ConfirmCard` 时**没有传 `externalContent`**；`ConfirmCard.externalContent` 默认 `false`（`packages/muyon_ui/lib/src/confirmation.dart:75`，`:158` 起据此决定提示和可选项）。批量确认卡同样要核。
- 宿主已有任务级的污染状态：`apps/muyon/lib/platform/grants/host_authorization_facts.dart`（`HostTaintState { clean, unknown, tainted }`，`requiresConfirmation => taintState != clean`）。
- 现在助手页打开 `DynamicWorkspace` 时不传业务动作（`assistant_page.dart:742`），所以此缺口暂时触发不了；AIUI-6/9 接上业务动作后就会暴露。本任务要在那之前把它堵上。

## 要求
1. 先读懂再改：理清动态界面从 `DynamicWorkspace` / `ConversationWorkspaceHost` 到 `DynamicUiSurface` 到确认卡的数据流，以及外部内容在 `ConfirmCard`、`BatchConfirmCard` 里分别影响什么（提示条、「全部允许」、持久选项）。在提交说明里用几句话写清楚。
2. 让动态界面里的确认卡和批量确认卡拿到「本任务是否含外部内容」：
   - 来源只能是宿主的污染状态（按产生这个界面的任务），**不能**来自计划、模型输出或界面状态；
   - **失败即关闭**：状态为 `tainted` 或 `unknown`、或者查不到，都按含外部内容处理；只有 `clean` 才是 `false`；
   - 改动尽量小：沿现有构造参数或控制器传递，不新建抽象，不改授权判断本身。
3. 不改 ADR、不放宽任何现有确认；不碰 `inquiry_record_tools.dart`、授权库与工具注册。

## 测试（先写测试，看它失败，再改）
- 污染、未知、查不到三种情况下，动态界面里的确认卡显示外部内容提示，批量卡没有「全部允许」；`clean` 时行为与现在相同。
- 计划或界面状态里伪造一个「外部内容 = false」的值，不能把污染任务变成干净。
- 变异自检：把传入的标记改回固定 `false`，上述拒绝路径测试必须失败；恢复后再跑通过。
- 跑 `packages/muyon_ui` 与 `apps/muyon` 的 `flutter analyze`（info 也算失败）和受影响的测试文件；再跑一次 `apps/muyon` 全量 `flutter test`。跑测试时保留代理设置，只把 `localhost,127.0.0.1,::1` 加进 `NO_PROXY`；不导出 `MUYON_EVAL_REAL`。

## 约束
只格式化改动过的文件；原始日志不进仓库；不合并 develop；不改 `analysis_options.yaml`。发现范围外问题，写进回报，不顺手修。

## 回报
分支与提交哈希（`git ls-remote` 确认已推）；数据流说明；改了哪些文件；新增测试名与结果；变异结果；analyze 与全量测试的通过/失败/跳过数；遗留问题。
