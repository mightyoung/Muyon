# Skill / Connector 生产链路缺口与接口交接

日期：2026-10-23。设计候选，不是运行服务交付。

## 固定输入与权限

基线 `d2c56a626736fa85a95cbf8f52d5dba85fc04be3`；接续综合候选 `41f5e702ea3ef4b09783e87916c57e46c6c214c4`。云端负责人已由用户确认停止写入；本地 root 为唯一 develop 集成人。公共类型、Operation、FFI 和模块登记均由 root 串行维护；其他 owner 只交候选。

现有 `services/commands.rs::HostCommandPort` 是抽象合同；`connections.rs` / `skill_runtime.rs` 是纯校验、恢复与投影。它们不派发生产请求，不证明授权，也不持久保存草稿。`SkillRunSnapshot.job` 是一个文档步骤快照，不能代表整个 Skill 运行进度。

## 实际调用边界

| 边界 | 现状 | 后续唯一 owner 与交付条件 |
| --- | --- | --- |
| requestRun → 原 Operation | `contract.rs::Operation` 没有 SkillRun / ConnectorCall 等变体，不能借 ProjectCreate 或任意 JSON 外壳执行 | Contracts/root：先固定具名 variant、规范摘要字段、披露与预算、原回执语义，再交内核测试；目前不开放 requestRun |
| HostCommandPort → ProductCore | ProductCore 已有 prepare / confirm_user_plan / lookup_original / cancel_original，尚无完整公共服务适配器 | Host/FFI owner（本轮 root 保管，尚未授权接线）：实现严格 codec 适配，仅支持已有 Operation；不创建第二 Intent/Receipt/RunLedger |
| 授权代次及 prepared 失效 | CallBinding 能比较 config / authorization / catalog / plugin revision；ProductCore 的通用 Prepared 只保存 command / dispatched | Connector owner 提供可信当前快照，Host owner 在派发同一锁/事务边界校验完整绑定；Contracts 定义原计划与绑定的关联，不能把 UI 提交的 current 当可信当前值 |
| Skill 每步执行 | decide_step 校验 host ∩ plugin ∩ descriptor ∩ connection | Skills owner：在原 workflow owner 移交后逐步接线，每步重取可信权限，停止后的步骤不可派发；不得自建运行账本 |
| 取消 / 排空 | cancel_original_run 适配原取消；validate_lifecycle_change 只校验快照 | 原执行 owner 收束已派发效果；Connector owner 停接新调用并标记失效；UI 显示 cancel_requested，收到原 owner 停止证据才能显示已停止 |
| 原意图恢复 | lookup_original_run / recovery_for 已保留原 IntentId | Host owner 查询原 owner；超时、重启、断网不重新 prepare / confirm；not_submitted 只按原返回处理 |

## 拟议适配接口（非已冻结公共 API）

沿用现有 `HostCommandPort` 四方法，不新增通用 method-string dispatcher。Host 实现的概念映射如下：

```text
prepare(Operation, project_id, expected_revision)
  -> ProductCore.prepare(strict_operation_json, project_id, revision_string)
  -> strict CommandEnvelope decode + binding validation
confirm(plan_id)
  -> trusted visible-confirmation callback only
  -> ProductCore.confirm_user_plan(plan_id)
  -> decode_original(raw, original_intent_id)
lookup_original(intent_id)
  -> ProductCore.lookup_original(intent_id) -> decode_original(raw, intent_id)
cancel_original(intent_id)
  -> ProductCore.cancel_original(intent_id) -> validate original ExecutionResult
```

适配器必须以内部 prepared 映射取得原 IntentId，不能信任调用者传入另一 IntentId。模型/插件不能获取 confirm 入口。方法调用失败但没有可信派发前证据时，统一保留 unknown / after_lookup，不能因错误发生在名为 prepare 的函数里就断言未执行。

拟议 `PreparedBinding` 关联原 plan_id / intent_id、scope account/workspace/generation、SkillRef 与输入 digest、binding revision、Connection id / external identity / endpoint digest / config revision / authorization generation / catalog revision / plugin binding revision。此记录是原 plan 的失效前置条件，不是新命令账本；字段来源必须是可信宿主。确切结构和存储位置需原 owner 审查后冻结。

## 状态不变量及验收

1. prepare 与 confirm 之间任一绑定或授权代次变化：原 prepared 失效，dispatch_count 为零；不静默刷新后执行。
2. confirmed/dispatch 后失联：保留原 IntentId，lookup_count 增加但 prepare/dispatch_count 不增加；跨账号查询拒绝。
3. disable/disconnect/revoke_requested：先阻新调用、失效 prepared，再由原 owner 排空旧调用。disconnect 不证明 token 已撤销；撤销超时保留未知。
4. cancel_requested 后晚到原成功回执：保留真实成功，不伪造成 cancelled 或 rollback。步骤终态不推导整个 Skill 终态。
5. 同一连接的不同插件仍按各自 binding 过滤；同名 tool/resource/prompt 按种类和 schema digest 分开。
6. 文档形状检查和引用字符串不证明可信解析/权限。Reader/FD 继续由原受控 reader owner 授权；FD lease 未设计前不可开放。

验收分开：纯 fake 状态/恢复测试 → ProductCore 现有 Operation 适配集成测试 → 进程重启/授权变化测试 → 真实 consent/transport/取消排空。每层保留精确源码 SHA；前一层通过不代替后一层。

## 未决 gate 与下一片

| 未决项 | 必须补齐的设计 | gate 关闭前行为 |
| --- | --- | --- |
| 通用草稿持久化 | 独立插件 namespace、schema 升级、CAS、原保存意图恢复、SaveAck；不能借用 Bot 数据库 | DM01 只 fake host 与序列化恢复，不声称保存 |
| 可信来源解析 | 来源类型、实例/仓库/对象/SHA身份、权限重新检查、Reader/FD 租约、过期与撤权 | 形状合法仍不可解析/授权 |
| MCP SDK | 官方包/协议固定版本、维护/许可证、认证/刷新、取消/资源释放、平台支持比较；另交 SDK 决策候选 | 无新 SDK、OAuth、WebHook 或真实 MCP 服务 |
| SkillRun / 具名 Connector Operation | 原 contract、参数规范摘要、授权/预算、确认、原 owner 恢复 | requestRun / requestCall* 保持不可用 |

下一片只做已存在 Operation 的 HostCommandPort 适配设计评审与 fake codec 测试；任何新 Operation 或生产接线都等上述具体接口审查。本文仅静态对照源码；未执行真实模型、网络服务、持久化、Android、生产权限或部署验证。
