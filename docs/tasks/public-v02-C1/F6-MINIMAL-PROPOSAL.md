# F6 最小契约提案 · 未冻结

本稿只列父任务要求的跨模块选择，等待裁定；不是新增架构/依赖/权限。当前产品基线为 fd26dcdabcdac996bc2881e8141cac2b519966fc，旧 7aa 为历史。当前本地 C1/C2/C3 草稿不向其他线宣布已冻结或已合入。

## 已核实且可直接执行

- ProductError 只有 Failure { code: String }，无可信阶段/派发信息。C2 默认 error=unknown_outcome、effectKnowledge=unknown、retryability=after_lookup，保留原 IntentId。not_started 仅可由适配器本地调用前校验或原 owner 的明确未派发证据产生，不能从错误枚举或 phase 标签推断。无需改 ProductCore ABI。
- 原 contract::identity 限制非空、<=128 UTF-8 字节且仅 ASCII 字母数字及 -_.:；原 AgentOwner::id 相同。FFI 的 intent:32hex 为39字节，plan:32hex 为37字节。C1 公共不透明值的解析器不签发身份、不替代 CommandEnvelope::validate。已补原生成格式、128/129字节、129字节多字节及“公共值可解析但原命令拒绝”的 fixture。
- C2 取消视图须同时保留原 ExecutionStatus 和 cancel_requested：原 Pending/Unknown 均可展示 CancelRequested，但二者不能成为完全相同的视图。独立审查发现此缺口后，已用实际失败回归证明并修复；只是原状态投影，不新建执行状态权威。

## 待裁定的精确最小提案

### 1. phase 的值域

新增纯 Rust/serde 枚举 ServicePhase：Decode、Negotiate、Prepare、Confirm、Dispatch、Lookup、Cancel、DraftSave、HostCall；wire 使用 snake_case，字段名仍为 phase。HostCall 表示无更具体调用点信息，绝不表示已派发或未派发。用此枚举替代 ServiceError.phase: String。若后续需要 Ocr/Index 等子阶段，另有详情字段/具体 DTO，不在本轮无限扩展公共枚举。

该枚举只标观察/适配调用点，不充当可信派发证据；未知 major/安全相关未知值继续拒绝；未知 wire phase 不映射为 HostCall，Dispatch 也不能证明已派发。当前草稿实际只产生 decode/negotiate/host_call/draft_save，尚未冻结。

### 2. Money / Quantity

新增 DecimalText 私有字符串 newtype，以及 Money { amount: DecimalText, currency: String }、Quantity { value: DecimalText, unit: String }。不增加 decimal/单位依赖，不经 f64/JavaScript Number，不做运算、舍入或单位换算。

候选 DecimalText 语法为 -?(0|[1-9][0-9]*)(\.[0-9]+)?，拒绝 +、指数、NaN/Infinity、空格及整数前导零；保留小数尾零以保留原精度表达。负数/负零能否用于具体业务由领域规则判定，不在公共类型默默改值。公共层接受并逐字保留 -0/-0.00；1、1.0、1.00 仅按词法区分，不提供数值相等或比较。只接 JSON 字符串，拒绝 JSON number。直接 DecimalText::parse 也显式校验 raw.len() <= MAX_COMMAND_BYTES，不能误认为原 JSON 解码的整体上限会自动覆盖独立解析；整体 JSON 仍独立受原上限约束。

currency 校验3位大写 ASCII 字母；这只证明代码形状，不声称该代码已通过完整 ISO 4217 分配表核验。unit 拒绝纯空白和控制字符（含 NUL/换行），接受的原文不 trim、不改大小写、不做 Unicode 归一化。Money/Quantity 字段私有，Money::new(amount: DecimalText, currency: &str) -> Result<Self, ServiceError> 与 Quantity::new(value: DecimalText, unit: &str) -> Result<Self, ServiceError> 执行校验，反序列化通过同一构造器，借用 getter 只读访问。单位目录由既有领域 schema 版本及调用上下文绑定；脱离该上下文只展示原值，不推断单位意义或执行换算。缺币种/单位不默认补 CNY/个/零，未知业务口径保持未知。币种完整目录和单位换算不是本次新增引擎。

### 3. 旧处理结果到 ResultId

转换归 Documents/D1 owner，C1 只拥有 ResultId 值类型。建议新增 D1 helper：

`legacy_processing_result_id(processing_receipt_id: &str) -> Result<ResultId, ServiceError>`

仅接受原生成格式 processing-<64 lowercase hex>，映射为 result:legacy-processing:<同一hash>。D1 另外保留原 processing_receipt_id 的只读关联和完整 SourceVersion，不改变旧 owner 记录。该映射不证明原结果存在、可访问或提取成功：ProcessingReceipt 在 Unsupported/Failed 时也有 ID；D1 必须仍核对真实 owner 记录、ProcessingState 与 SourceVersion，不能因映射成功就发布可用文本结果。该 ResultId 不得与原业务 IntentId/Receipt ID 比较，也不成为新的执行或幂等账本。由 Documents owner 更新 D1 适配签名/fixture；Contracts 不抢改其产品文件。

## 未做事项

未实施以上跨模块选择、UI 校验迁 Rust、类型生成器选型、Office/PDF/Electron 新架构；未增加依赖或修改原 ABI。工具安装仅依用户明确批准的官方 Rust 与锁定缓存范围完成，产品验证保持 offline/locked。裁定后以测试先行补齐最小定义，再按 C1、C2、C3 分片提交固定候选 SHA；只有 B 决定合入。

独立静态提案审查（f6_contract_proposal_review）：上述最小方向可支持；已据审查明确直接解析限额、词法精度/负零、JSON string、构造器/反序列化一致校验、unit 控制字符/目录上下文及映射不证明处理成功。新规范仍待父任务裁定，不将审查建议当实施授权。
