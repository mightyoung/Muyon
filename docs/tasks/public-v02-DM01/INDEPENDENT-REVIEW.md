# DM01 独立审查

2026-10-23，root（非领域实现作者）审查 `d2d6a01e436bc7d9a5ad7dfa4de9a3af02542842` 相对 `d2c56a626736fa85a95cbf8f52d5dba85fc04be3` 的完整领域源码和17项测试。

未发现阻断本次纯领域候选的缺陷。结构化补丁支持多条 requirement/bug/question 与原消息字节范围绑定，稳定 item 不可换类型/来源；手改文本冲突先展示差异，旧 revision 整体拒绝。项目候选显式选择，跨项目 scope 拒绝。公共 DraftEnvelope / SaveAck / 原 CommandEnvelope 与 Receipt 均复用；唯一可准备的业务动作是现有 ProjectCreate。Unknown/Pending 恢复只查询原命令；派发 marker 在返回命令前设置，重复点击不能再次取命令；晚到终态不重建项目。

生产限制必须保留：这里的 SourceBinding 是保存的原消息形状，不证明可信消息来源或授权；ProjectHost 只有 fake query，没有模型、聊天 UI、真实授权或存储实现。宿主必须先持久保存 dispatch marker 再执行外部命令，崩溃恢复还须以持久化原 owner 账本核对。通用草稿 CAS/版本迁移/保存意图恢复仍需独立设计，不能借 Bot 草稿库或把本片序列化恢复当作持久化验收。

root 作为唯一模块登记 owner 补充真实库导出 `development_drafts`，并将 integration test 从 path include 改为公开库导入。登记后35项聚焦回归和最终 SHA 的 CI 结果由集成交付报告单列。
