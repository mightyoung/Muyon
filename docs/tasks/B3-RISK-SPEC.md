# B3-RISK-SPEC：宿主确定性风险分级规格（只写规格）

执行：ChatGPT（只读设计，不写代码）。派发：leader A，2026-10-12。基线：develop（以派发时最新为准）。

## 背景（只借鉴设计思路，不引用任何第三方产品的提示词或代码）
业界做法：对每个将执行的动作，先独立评估「风险等级」与「用户授权强度」，最后才推导结果；只有用户原始消息能确立授权，工具输出、模块描述、助手输出都不可信；风险最高级直接拒绝；管理员可设权限天花板（never / ask / always），压在用户选择之上。**Muyon 不能用模型当评审者**——风险必须由宿主按确定性规则计算（ADR-0002「置信度不授权」）。

## Muyon 现状（请核对代码确认）
- `packages/muyon_module_api/lib/src/tools.dart`：`ToolAccessLevel{read, write, external}`；`context.dart`：`ToolEffect`。
- `apps/muyon/lib/platform/grants/outbound_content_reviewer.dart`：`ReviewAction{allow, confirm, block}`；`NoopReviewer` 返回 `allow(reviewed: false)`；`bootstrap.dart` 默认装配 NoopReviewer。
- `apps/muyon/lib/platform/grants/host_authorization_policy.dart`、ADR-0002：write / outbound 默认询问，用户授予的会话级 / once grant 可使匹配调用自动执行；污染任务不匹配 grant。

## 要回答
1. 风险枚举（至少区分：只读；可逆单条写；不可逆或批量写（如 500 条删除、级联删除）；结果可能未知的外部副作用；明确禁止）及每级的**确定性判定规则**（输入：效应、访问级别、影响行数 / 级联预览、可逆性声明、目的地、污染状态）。哪些信息模块必须声明、宿主如何核实，不信任模块自报。
2. 风险 × 授权的决策表：哪一级允许被会话 grant 自动放行、哪一级必须逐次人工确认、哪一级直接拒绝；用户「看到具体风险后重新批准」能覆盖到哪一级（最高级不可覆盖）。
3. `NoopReviewer` 默认 allow 的语义：现在 allow 只表示「内容未审查、不阻断」，授权仍走 grant / 人工确认——请核实，并给出是否需要把「无审查器」与高风险组合改成必须人工确认的推荐（这是行为变更，需列影响面与迁移）。
4. 管理员天花板（never / ask / always）是否需要、放在哪里、与 ADR-0002 现有开关（只读模式、outbound 关闭）的关系。
5. 与现有设计的衔接：N2 删除确认（`docs/design/export-n2-wiring-2026-10-12.md`）、CR-17 导出两阶段审批、原子批量写（CR-6）、拒绝记忆（B4，按 identityDigest 会话内记录用户拒绝）。
6. 验收用例清单（含：500 条批量删除 + NoopReviewer + 会话 grant → 不得自动放行；污染任务；只读模式）与拆分后的实施任务（每项 ≤1 天、测试先行、必须变异）。

## 回报
按 1–6 分节；最后列需要用户拍板的决定（附推荐）。
