# AIUI 默认开启计划（条件目标，尚未执行）

日期：2026-10-10 · 用户已授权整理计划；本文仍未派工、未改默认开关、未触发构建/安装/发布。全部时间为北京时间（UTC+8）的**条件目标窗口**；执行负责人、设备、真实模型端点/授权/额度均未落实，条件不具备时顺延并更新状态页。

## 当前事实

- a68 `apps/muyon/lib/app/bootstrap.dart:323-328` 注册 `TaskReceiptUiPlanningSource`，`uiPlanningEnabled:false`。`agent_context.dart:208-226` 在开关启用时可于保存回答后自动规划；`assistant_page.dart:600-609,726-773` 仍提供手动开关/“规划此回答”/打开交互页/保存草稿入口。
- PR40 `650f51a` 的 `InquiryReadonlySnapshots` 和 `InquirySnapshotCard` 只有定义与测试，没有助手shell生产调用点。PR40合入或默认值改成true，都不能单独让询价事实卡在对话出现。
- `ui_planning_source.dart:15-69` 只从成功任务回执的恰好一个对象读取标为未核验的标量事实；不是PR40的当前已保存snapshot source。`personal_agent.dart:243-245` 配置只改内存；`screens/dynamic_workspace.dart:121-179` 只有打开动态workspace才调用持久化controller；harness最新计划是内存态。
- 当前云端无Flutter/Dart/ADB/Xcode工具链与Android设备；模型端点/凭据环境变量仅查存在性，未发现可用配置（不读取secret）。vivo V2324A是历史设备证据，不代表当前连接/可用。无可复用的本轮安装包证据。
- 已亲查 Actions 产物：[旧UI预览37935776194](https://github.com/mightyoung/Muyon/actions/runs/37935776194) 只有未过期 ui-preview-static-package，源为 `cfba2339a4e504207d039e1604631ff5badac4b0`；[verify37403628056](https://github.com/mightyoung/Muyon/actions/runs/37403628056) 只有日志，a68 CI只有coverage/log。这些都不是当前候选Android安装包，不能代替同SHA烟测；本轮不触发手动package-artifacts。
- 既有第二阶段指标照旧：[HANDOVER §4](HANDOVER-LEADER.md)：只读审批中位数0、写任务1；首字本机 `<1.5s`、远程 `<3s`；新外壳询价North Star需真实模型+真机；并要求授权测试、CI和能力覆盖。卡片可见延迟目前没有已采纳阈值。

## 条件目标窗口

| 窗口（北京时间） | 负责人 / 依赖 | 目标验收 | 失败顺延 |
|---|---|---|---|
| 10/11 09:00–12:00 | AIUI-6/对话规划owner（待确认）；root唯一integrator；非作者reviewer | 先读回PR40审查、新基线CI；接通真实snapshot→助手卡片shell，并补设置持久化opt-out。证明事实/建议分离、可信来源与范围、scope撤权/旧pin、敏感字段遮盖、提交禁用；加真实宿主读取测试。代码先独立review。依赖未审/组合未绿则不进入候选。 | 10/12同窗；不以PR40本身代替接线与opt-out。 |
| 10/11 13:00–14:00 | root/integrator、设置owner、非作者reviewer（待确认） | 在接线与持久opt-out已通过审查后，单独提交“默认开启”受测候选；source/测试验证冷启动默认值、关闭选择持久化，核对远端/外传gate和写入确认未放宽。此为未发布候选，不集成、不安装、不构建新包。 | 前置未过则移至10/12同窗；不先启用/发布。 |
| 10/11 14:00–17:00 | QA及有设备执行者待root指派；AIUI owner配合 | 仅在真实模型端点/授权/额度和**已获准可复用安装包**均具备时，对同一受测候选做Android/真实模型冒烟：卡片可见、真实/离线降级、取消/超时、scope失效、重启恢复及opt-out持久性；记录设备/OS/model与步骤。不得为此新建package-artifacts或安装未经授权的包。当前资源未落实则记录阻塞。 | 有资源/已授权包后排10/12 13:00–17:00；缺任一条件均顺延或申请授权。 |
| 10/12 09:00–12:00 | root/integrator、设置owner、非作者reviewer（待确认） | 只有上述适用门槛与审查证据齐全后，才正常集成候选并核对精确发布CI；不在CI未完成/失败时宣称启用成功。新包构建/安装/发布不在本计划授权内；若无已获准可复用包，设备安装验收保持阻塞并另行申请授权。 | 任一必要证据/审查/CI未通过则不集成/发布；给出新窗口，不跳门槛。 |

## 验收矩阵

在默认开启候选同一SHA下记录证据，不把离线fixture写成真实模型/真机：

1. **真实接线与来源**：shell消费宿主真实snapshot；保存事实和建议分离；source label与对象/修订对应；敏感/未核验值按规则遮盖；所有业务提交仍禁用。验证selected scope、撤权、pin/revision变化都阻止展示旧数据。
2. **生命周期与退路**：取消、超时、错误/空事实、无模型与离线固定模板；重启恢复已保存卡；用户关闭后重启仍保持opt-out。配置须先持久化，不能把当前内存设置冒称可恢复。
3. **授权**：只读事实读取不新增业务确认；写入、外传及未授权远端模型端点保留[ADR-0002](../adr/0002-graded-assistant-authorization.md)门槛；读取授权不得扩大scope。
4. **性能记录**：按E-1同口径记每次首字延迟与中位数并对照既有本机/远程目标。卡片可见定义为“提交后到首个已保存事实卡完整布局可见”，至少5次记录原始单次值和中位数；目标阈值另由验收方案确认，不自行加门槛。
5. **发布证据**：固定源SHA、独立review、全8套CI。14项完整场景逐项登记完成/进行/阻塞；未做项继续未验收，不能声称AIUI-6整任务完成。只读已接线切片按自身边界验收，不以虚构“14项全部通过”作为先决条件。

本页的目标时间不代表预约或设备/额度已落实。缺少外部执行条件时，将状态记为阻塞并顺延；不构建或安装应用，不修改权限/CI门禁，不启用默认值。
