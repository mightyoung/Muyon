# Connector 目录、连接实例与 MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 先交付本地 Connector 声明/连接快照和权限恢复规则，MCP SDK 待固定包评估后才接线。
**Architecture:** 描述符、Connection、插件 Binding、能力目录分开；凭据由可信宿主保管；所有外部效果仍归原 IntentId/Receipt。
**Tech Stack:** 现有 Rust/serde；本地 fake transport；无新增 SDK。
**Spec:** [v0.2](../specs/2026-10-23-public-services-ui-design.md) §4 Connector、6、10–11。
**Baseline:** [总索引](2026-10-23-public-services-index.md) 约束适用。

## Global Constraints

- 外部集成统一叫 Connector，MCP 是协议，不等同全部连接方式或 OAuth。
- 发现不等于授权；重连或新增工具不自动扩大允许集合。
- secretRef 与普通配置分离，裸凭据不进入 Skill、UI、日志或回执。
- 超时、取消及错误返回不自动证明未执行，保留 unknown_outcome。
- 本轮无真实同意流程、账户连接、远端读取或安装行为。

## Review Focus

- 已认证但目录刷新失败：X1 分轴，不能返回空目录冒充成功。
- 账号/端点/目录/授权代次变化：X2 拒绝旧 prepared。
- 远端自报 readOnly 与恶意 prompt：X2 不扩大调用许可。
- 超时已发出、本地断开、撤令牌失败：X2 保留未知和原 owner。
- SDK 固定包许可与 Android API 不兼容：X3 先 gate 后依赖。

## 真实基础和术语

现有 Rust 的可信授权与执行在 `contract.rs`、`business.rs`、`agent/owner.rs`；
Android 外发接线在 `product/agentipc/ProductService.kt` 与 `chat/ProductChatRuntime.kt`。它们不是统一 Connector 生命周期。旧 Dart 集成只用于语义参考，不能直接恢复旧凭据路径。

研究候选是 rmcp-v3.7.0 与 Kotlin SDK 0.15.0；固定包 LICENSE/NOTICE、MSRV、Ktor engine、Android minSdk 尚需核验。当前 app minSdk=26/JVM17，不能从“JVM 可编译”推断 Android 可用。

## X1：纯本地目录、连接与绑定只读模型

**Owner:** Connectors。**Files:** 新增 `crates/muyon-core/src/services/connectors.rs`、`tests/public_connectors.rs`、`docs/contracts/public-services-v02/fixtures/connectors.json`；mod.rs 登记由 Contracts。依赖 C1；本片不带 transport 或 credential store。

**Interfaces，新增：**

```rust
enum ConnectorProtocol { Mcp, Http }
enum AuthMethod { None, OAuth, ApiKey, HostManaged }
struct ConnectorRef { connector_id: String, adapter_version: String, descriptor_digest: Digest }
struct ConnectorDescriptor {
    reference: ConnectorRef, protocol: ConnectorProtocol,
    config_schema: serde_json::Value, auth_method: AuthMethod, declared_capabilities: Vec<String>,
}
enum CapabilityKind { Tool, Resource, Prompt }
struct CapabilityEntry { name: String, kind: CapabilityKind, schema_digest: Digest }
struct CapabilityCatalog {
    connection_id: String, protocol_version: String, catalog_revision: Revision,
    fetched_at_unix_ms: UnixMs, fresh: bool, entries: Vec<CapabilityEntry>,
}
enum AuthState { NotConfigured, ConsentRequired, Authorized, Expired, Revoked, Unknown }
enum CatalogState { NotReady, Ready, Partial, Failed, Unknown }
enum NetworkState { Disconnected, Connected, Unknown }
enum Availability { Available, Unavailable, Unknown }
struct ConnectionSnapshot {
    connection_id: String, connector: ConnectorRef, scope: ScopeRef,
    endpoint: String, external_identity: Option<String>, config_revision: Revision,
    authorization_generation: Revision, auth: AuthState, catalog: CatalogState,
    network: NetworkState, availability: Availability,
}
struct ConnectionBinding {
    binding_id: String, connection_id: String, owner_plugin_id: String,
    scope: ScopeRef, revision: Revision, allowed_capabilities: Vec<String>,
}
fn get_descriptor<'a>(descriptors: &'a [ConnectorDescriptor], reference: &ConnectorRef)
    -> Result<&'a ConnectorDescriptor, ServiceError>;
fn get_capability_snapshot<'a>(catalogs: &'a [CapabilityCatalog], connection_id: &str)
    -> Result<&'a CapabilityCatalog, ServiceError>;
fn validate_config(descriptor: &ConnectorDescriptor, public_config: &serde_json::Value)
    -> Result<(), ServiceError>;
```

P1 的 config_schema 只接受可信内置 schema，由显式字段校验实现；不引入任意 schema 解释器。public_config 中 password/token/client_secret 等敏感字段一律拒绝，不能只在日志中掩码后继续；秘密引用仅在后续可信配置 owner 内存储，不序列化进 ConnectionSnapshot。endpoint 对外投影移除 userinfo/query/fragment，不能把含密钥 URL 放 UI/日志；业务请求仍使用可信宿主解析的原端点，不从 UI 投影还原。

listConnectors/getConfigSchema/getConnection/getBinding 是对宿主已过滤 snapshot 的读取，不探测网络。registerDescriptor/setEnabled/retireVersion 只登记可信适配器元数据，不下载/运行程序；持久命令 gate 见 X2。

- [ ] `auth_and_catalog_states_are_independent`：Authorized+CatalogFailed 不等于不可认证或空成功；缺目录返回 CapabilityUnavailable，不偷偷 refresh。
- [ ] `no_secret_in_public_projection`：token/userinfo/query 中 sentinel 不出现在 JSON/debug/safeMessage；含敏感配置拒绝；getter transport invocation=0。
- [ ] `capability_kinds_are_separate`：相同 name 的 tool/resource/prompt 不混用，重复同 kind/name 拒绝。
- [ ] RED/GREEN：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connectors`，先行为断言失败再实施。
- [ ] 提交 `feat: model connector catalogs and connection snapshots`，审查所有读取都只读已有快照。

## X2：连接变更、具名请求和未知效果的宿主判定

**Owner:** Connectors。**Files:** 新增 `services/connections.rs`、`tests/public_connections.rs`；不修改原账本。依赖 X1/C2；S2 消费其授权交集而不持有 secret。

**Interfaces，新增：**

```rust
struct CallBinding {
    connection_id: String, external_identity: String, endpoint_digest: Digest,
    config_revision: Revision, authorization_generation: Revision, catalog_revision: Revision,
    plugin_binding_revision: Revision,
}
enum RemoteRequest {
    CallTool { name: String, schema_digest: Digest, arguments: serde_json::Value },
    ReadResource { name: String, schema_digest: Digest, resource_ref: String },
    GetPrompt { name: String, schema_digest: Digest, arguments: serde_json::Value },
}
fn validate_call(expected: &CallBinding, current: &CallBinding,
    current_scope: &ScopeRef, request: &RemoteRequest, catalog: &CapabilityCatalog,
    binding: &ConnectionBinding, host_allowed: &[String]) -> Result<(), ServiceError>;
enum RemoteEffect { NotDispatched, Confirmed, Unknown }
fn recovery_for(effect: RemoteEffect, intent: &IntentId) -> Result<IntentId, ServiceError>;
```

validate_call 检查 binding.scope == current_scope。binding/current 都由可信宿主在派发前同一临界区解析，不解码模型送来的“当前授权”。还需 exact connection/scope/目录版本、新鲜度、schema 摘要和当前 host/plugin allowed 集合；工具自报只读只是提示，不能决定是否走命令链。资源/prompt 读取通常外发，同样受宿主披露/预算策略检查。此片纯校验不返回成功 Receipt；RemoteEffect::Confirmed 只代表原 owner 确认某调用效果，并不代表业务验收。

configure/bind/requestConsent/requestConnect/requestReconnect/requestRevoke/refreshCapabilities 的公共签名冻结前必须由 gate 补原 Operation 及 host identity 来源；P1/P2 只验证相应状态转换和失效，不直接执行。生产请求统一映射 C2 prepare → confirm → original lookup；requestCallTool/requestReadResource/requestGetPrompt 是具名动作，不能给调用者任意 IPC method 字符串。

- [ ] `binding_changes_invalidate_calls`：外部身份、端点、config、授权代次、catalog、插件绑定 revision 各变一项均拒旧 prepared；目录新增 write 不进入 allowed 集合。
- [ ] `same_connection_does_not_share_plugin_permissions`：科研 only read、询价 only quote、研发 only repo，复用 connectionId 仍不能调用邻域工具；跨 scope 拒绝。
- [ ] `remote_read_and_prompt_require_host_gate`：远端 readOnly=true 或 prompt 要求忽略权限都不能使未授权调用通过。
- [ ] `timeout_and_disconnect_preserve_original`：fake transport 已发出后 timeout → Unknown，原 IntentId 查询，dispatch_count=1；本地断开不等于 token revoked；停用阻止新动作但保留旧结果；取消不生成 rollback 证据。
- [ ] RED/GREEN：`cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_connections`；不启动 localhost server 或真实账户，仅内存 fake。
- [ ] 实施校验/恢复判定，生产 dispatch 维持不可用；审查 C2 协作点必须有具体 Operation 才能启用。
- [ ] 提交 `feat: validate connector calls against current host bindings`，报告 fake 覆盖与真实认证/撤权 NOT_RUN。

## X3：MCP SDK、认证与资源生命周期工程 gate

**Owner:** Connectors。**Files:** 先新增 `docs/implementation/public-services-mcp-sdk-gate.md`、`docs/tasks/public-v02-X3/REPORT.md`；未来 `services/mcp.rs` 在 gate 批准后才创建。依赖 X2、宿主凭据设计、具体许可/Android 评估；不先改 Cargo/Gradle。

**Inputs/outputs:** 输入研究固定候选 tag、app minSdk26/JVM17、现有依赖清单与 X2 CallBinding；输出固定包 SHA/许可证/NOTICE/依赖闭包、Android API/ABI/MSRV/feature 表、MCP 协议兼容范围、选型或拒绝原因。Rust fixed-tag 许可原文缺失须保留阻断。

- [ ] gate RED：固定包许可/Android 兼容/凭据 owner/同意与撤权语义未明确任一项，审查拒绝安装与接线。
- [ ] 确定 credential store 的具体宿主 owner 与 secretRef 访问/清理/过期流程；不接受模型/UI 构造 secretRef 授权；换账号/端点/扩权使旧 prepared 失效。
- [ ] 明确 MCP initialize、分页 tools/resources/prompts、schema/catalog 更新、断连重连、错误/超时/取消、流关闭的受限适配；MCP request id 仅关联协议，不作 IntentId。
- [ ] 在 gate 文档中补 exact 适配签名与测试文件、RED/GREEN/Android 编译命令后另审。只准使用自建内存或已授权 mock fixture，真实 OAuth/服务端 revoke/网络探测不因 gate 通过获得授权。
- [ ] gate GREEN：所有固定证据齐全且书面选择得到评审；无 SDK 安装或线上兼容通过声明。
- [ ] 提交 `docs: assess pinned MCP adapter prerequisites`；真实连接/付费/扩权/外部写入仍各自授权。

## X4：多仓库信息同步与规范化来源事件设计 gate

**Owner:** Connectors；Domain 拥有任务关联/进度规则。**Files:** 先新增 `docs/implementation/public-services-repository-events.md`、`docs/tasks/public-v02-X4/REPORT.md`；通过前不创建真实应用、不配置凭据/Webhook、不写同步服务。依赖 X1/X2、父任务的三方官方能力研究和研发独立设计评审。

**Inputs/outputs:** `reviewRepositoryAdapters(providerEvidence, connectionCapabilityModel, domainProgressNeeds) -> {providerCapabilityMatrix, normalizedEventSchema, inboundDedupRules, reconciliationRules, hostCommandMapping, unsupportedAndUnknown}`；providerEvidence 必须含 GitHub/GitLab/Gitee 的固定阅读日期、官方链接与具体版本/能力。该签名是文档交付，不是网络执行 API。

- [ ] 分 provider 列 commit、push、branch、PR/MR、CI、issues 的 API/Webhook/轮询/缺失/未知，保留 PR 与 MR 差异；Gitee CI 不假设与 GitHub 同构。没有官方证据不能填 supported。
- [ ] 规范化事件候选字段：provider、connectionId、外部租户/仓库稳定 ID、deliveryId/eventId、eventKind、externalObjectId、headSha、baseSha、testedSha、发生/观察 UnixMs、providerRevision、catalogRevision、授权代次、sourcePayloadDigest、原始事件类型和完整性标记。缺失字段显式 unknown，不能拼出 SHA 或成功状态。
- [ ] 入站验签与接收 owner 保管 payload，去重键以 provider+connectionId+repoId+deliveryId 绑定；重复投递去重仅处理入站来源，不替代 C2 原业务执行身份。乱序/缺失/删除/撤权/断线须按 provider 的游标与增量/全量受限对账核验，不能承诺全局 exactly-once。
- [ ] getter 只读已有同步快照；联网拉取、健康检查、目录刷新仍按实际外发进入宿主授权；持续同步需用户授权的后台范围与预算，不能因产品需求就立即创建真实 Webhook。
- [ ] 文档 RED：新 SHA 被旧 CI 覆盖、push 被当验收完成、分支删除被当数据不存在、重连扩权或未核验事件直接改变任务时均审查拒绝；GREEN 是上述反例的可审阅映射与未来 RED/GREEN 测试入口明确，不是实际连接已通过。
- [ ] Domain 消费规范来源事实，按可配置规则生成进度变更候选；自动状态变更也必须宿主规则与原 IntentId/Receipt，验收/合入/发布事实各自独立。事件 deliveryId 不当业务 IntentId。
- [ ] 提交 `docs: map multi-provider repository sync prerequisites`，后续选型/同步实施须另审 exact API、测试和连接范围。

## 回退与验收

断开/停用只阻新调用并使 prepared 失效；原 owner 继续核对已派发操作。回退保持 connection history、原回执、unknown 与撤令牌未知状态，不删除审计以制造“已断干净”。验收需分本地合同、mock 协议、Android 编译、真实 consent/remote effects；本轮仅规划，后三者无新通过证据。
