# 写卡所需的模块契约扩展设计（GB-5）

日期：2026-10-11 · 任务：[GB-5](../tasks/GB-5.md) · 执行：工程师2号（grokbot）· 分支：`review/gb-5-write-card-contract` · 审查：leader A

依据：[CR-2 本体写卡设计](../design/ontology-write-cards-2026-10-11.md) 第 1、4、5 节（本分支检出时该文件尚未合入；正文按 `99bde9a` / `review/cr-3-5-chatgpt-20261011` 稿阅读）· [ADR-0004](../adr/0004-module-contract-v2.md) §4.2–4.6 · [REG-4c](../tasks/REG-4c-REPORT.md) · [GB-2](../tasks/GB-2.md)（科研写入形态；交付物在 `review/gb-2-research-write-contracts` 的 `docs/reviews/2026-10-11-research-write-contracts.md`）· [GROK-5](2026-10-09-inquiry-ontology-cards.md)。

方法：只读 `packages/muyon_module_api`（`module_v2.dart`、`ontology.dart`、`optional_capabilities.dart`、`tools.dart`）、`apps/muyon/lib/platform/inquiry_record_tools.dart`、`packages/supplier_core/lib/src/{quotation,values,assistant_actions}.dart`、询价适配 `apps/muyon/lib/app/adapters/inquiry_module.dart`、科研 `module_declarations.dart` / GB-2 结论。**未**改业务/测试代码；**未**运行 Flutter。推测标「推测」；静态看不清处写「未能静态确认」。

CR-2 的 D1～D11 用户尚未定；下文按 CR-2 **推荐假设**，假设处标明。

---

## 0. 读前摘要

| # | CR-2 缺口 | 最小契约落点 | 旧模块不实现时宿主退路 |
|---|---|---|---|
| 1 | 按「类型 × 操作」声明可写字段、创建是否可用、校验入口、关系写入约束 | 新可选能力 `WriteFormCapable` + `ModuleFeature.writeForms`；声明表落 `write_forms.dart` | 宿主**不出**可提交写卡；保留现有具名写工具/人工页入口；不得用跨类型字段并集猜可写面 |
| 2 | 提交前完整校验（规范化候选 + 多错误 + 字段路径） | `WriteFormCapable.validateDraft` → `WriteValidationResult` | 不调通用写工具；卡停留草稿并提示「模块未提供提交前校验」；不得把 preflight 当完整校验 |
| 3 | 结构化冲突（稳定错误码、字段路径、当前版本） | `ToolCallResult.data` 约定受信键 + 可选 `WriteConflict` 辅助类型（`tools.dart` 旁） | 仍 `failed`；宿主仅展示 `summary`，**禁用**三方冲突 UI / 强制覆盖；不得解析中文摘要 |
| 4 | 宿主受控只读业务回执查核 | 新可选能力 `BusinessReceiptLookup` + `ModuleFeature.businessReceipts` | 恢复时仅认宿主 `tool_invocation_receipts`；业务 `operation_id` 未知则保持「结果待核实」，**禁止**换 ID 重发 |

任务片建议五片：API 骨架 → 询价校验/可写面 → 结构化冲突 → 回执查核 → 写卡接线（卡片侧不在本设计实现）。

---

## 1. 四项最小接口草案（`packages/muyon_module_api`）

### 1.1 放哪里

| 文件 | 内容 |
|---|---|
| 新 `lib/src/write_forms.dart` | 写表单声明、`WriteValidationResult`、`WriteFormCapable` |
| 新 `lib/src/business_receipts.dart`（或并入 `write_forms.dart` 若希望少文件） | `BusinessReceiptLookup`、`BusinessOperationReceipt` |
| 改 `lib/src/module_v2.dart` | `ModuleFeature` 增 `writeForms`、`businessReceipts` |
| 改 `lib/src/optional_capabilities.dart` | 导出说明：与现有 `ImportCapable` 同模式 |
| 改 `lib/src/tools.dart`（可选轻量） | 文档化 `ToolCallResult.data` 受信冲突键；可选 `WriteConflict` 值类型（无行为） |
| 改 `lib/muyon_module_api.dart` | export 新库 |
| **不改** | `BusinessModule` / `BusinessModuleV2` 抽象成员数量；v1 测试夹具仍可只实现四成员 |

兼容原则同 ADR-0004 §4.1：新增接口 + `features` 交叉校验；宿主 `is WriteFormCapable` 且 `features` 含对应枚举才调用。

### 1.2 缺口 1 — 类型 × 操作的可写声明

```dart
/// 写卡操作面。与 REG-4c 工具尾缀对齐；关联卡映射为 [update]（CR-2 §5）。
enum WriteFormOp { create, update, delete, restore }

class WriteFieldPolicy {
  const WriteFieldPolicy({
    required this.field,
    this.create = true,
    this.update = true,
    this.requiredOnCreate = false,
    this.clearable = true,
  });
  final String field;
  final bool create, update, requiredOnCreate, clearable;
}

class RelationWriteConstraint {
  const RelationWriteConstraint({
    required this.relation, // RelationSpec.name
    this.allowUpdate = true,
    this.requireTargetInScope = true,
    this.submitFullListForRefList = true, // CR-2：refList 交完整最终列表
  });
  final String relation;
  final bool allowUpdate, requireTargetInScope, submitFullListForRefList;
}

class ObjectWriteForm {
  ObjectWriteForm({
    required this.objectType,
    required List<WriteFieldPolicy> fields,
    this.creates = true,
    this.updates = true,
    this.deletes = true,
    this.restores = true,
    this.humanOnlyReason, // 非 null → 该类型不出助手可提交卡
    List<RelationWriteConstraint> relations = const [],
  });
  final String objectType;
  final List<WriteFieldPolicy> fields;
  final bool creates, updates, deletes, restores;
  final String? humanOnlyReason;
  final List<RelationWriteConstraint> relations;
}

/// features: ModuleFeature.writeForms
abstract interface class WriteFormCapable {
  /// 本模块可写卡对象的声明；未知类型视为不支持。
  List<ObjectWriteForm> get writeForms;

  ObjectWriteForm? writeFormFor(String objectType) =>
      writeForms.where((f) => f.objectType == objectType).firstOrNull;

  /// 提交前校验入口（缺口 2）。只读；不得写库、不得签发审批。
  Future<WriteValidationResult> validateDraft(WriteDraft draft);
}
```

可写字段推导（宿主侧，CR-2 §1 推荐）：

`可编辑 = ontology.fields ∩ writeForm.fields(按 op) ∩ 宿主编辑器支持的 Kind ∩ 当前用户/范围允许`

任一缺失 → 该字段只读退路或整卡不可提交（创建必需且无受信默认时整卡不可提交，CR-2 A05）。

**旧模块退路**：无 `writeForms` 特征 → 宿主不生成通用写卡；现有 `inquiry.record_quote` 等具名工具与人工页仍可用。

### 1.3 缺口 2 — 提交前完整校验结果

```dart
class WriteDraft {
  const WriteDraft({
    required this.objectType,
    required this.op,
    this.id,
    this.expectedVersion,       // 询价：int 行版本；科研：见 §3
    this.expectedContentDigest, // 科研常用
    this.baseline = const {},   // 可信当前保存值（编辑/关联）
    this.values = const {},     // 仅改动字段；创建可为全量草稿
    this.draftRevision,         // 宿主草稿修订；晚到结果丢弃
    required this.scopeProof,   // 宿主钉住的范围证明（不透明）
  });
  final String objectType;
  final WriteFormOp op;
  final String? id;
  final int? expectedVersion;
  final String? expectedContentDigest;
  final Map<String, Object?> baseline, values;
  final int? draftRevision;
  final Object scopeProof;
}

class FieldIssue {
  const FieldIssue({
    required this.code,       // 稳定码，如 'required' | 'type' | 'range' | 'unknown_field'
    required this.fieldPath,  // 如 'name' / 'item_ids[2]' / 'price_tiers[0].min_qty'
    required this.message,    // 给人看；不得作为宿主分支依据
  });
  final String code, fieldPath, message;
}

class WriteValidationResult {
  const WriteValidationResult.ok({
    required this.normalized,
    this.draftRevision,
    this.dependencyProof,
  })  : issues = const [],
        formBlocked = false;
  const WriteValidationResult.invalid({
    required this.issues,
    this.formBlocked = true,
    this.normalized,
    this.draftRevision,
  });
  final List<FieldIssue> issues;
  final bool formBlocked;
  final Map<String, Object?>? normalized; // 成功时必有；失败时可带部分规范化供展示
  final int? draftRevision;
  final Object? dependencyProof; // 可选：关联存活等只读证明
  bool get isValid => issues.isEmpty && !formBlocked;
}
```

要点：

- 调用时机在**确认摘要冻结前**（CR-2 §4）；失败 → 不调写工具、不签审批（A22）。
- `draftRevision` 不匹配 → 宿主丢弃结果（A23）。
- **首版允许逐次发现错误**（CR-2 D11 推荐），但返回形状必须已是列表，避免二次改契约。

**旧模块退路**：无能力则宿主不进入「待确认」；可显示只读摘要 + 固定业务入口。

### 1.4 缺口 3 — 结构化冲突（工具仍 `failed`）

不新增 `ToolCallStatus` 枚举值（避免破坏回执 JSON 与既有测试）。约定：

```dart
/// 当 status == failed 且属并发/版本冲突时，data 可含受信键（宿主写入，不信模型）。
/// 稳定码示例：version_conflict | scope_changed | referencing_changed | operation_id_reuse
class WriteConflict {
  const WriteConflict({
    required this.code,
    required this.currentVersion, // 询价；科研可用 revisionRef/digest 字符串放入 details
    this.fieldPaths = const [],
    this.details = const {},
  });
  final String code;
  final Object currentVersion;
  final List<String> fieldPaths;
  final Map<String, Object?> details;

  Map<String, Object?> toTrustedData() => {
        'error_code': code,
        'current_version': currentVersion,
        if (fieldPaths.isNotEmpty) 'field_paths': fieldPaths,
        if (details.isNotEmpty) 'details': details,
      };
}
```

执行层（询价今天）：`expected_version` 不符时 `inquiry_record_tools.dart:422-423` 抛 `FormatException`，外层收成 `ToolCallStatus.failed` + 中文 `summary`（`:529-532`），**data 无稳定码**（静态可见；`inquiry_general_write_tools_test` 只断言 `failed`）。

建议改动（实现片，非本文提交）：冲突路径构造 `ToolCallResult(status: failed, summary: …, data: WriteConflict(...).toTrustedData())`，且**不写** `reg4c:` 回执行。

**旧模块退路**：无受信键 → 宿主只展示失败摘要，不开三方差异卡，禁止「强制保存」（CR-2 A27–A28）。

### 1.5 缺口 4 — 宿主受控只读业务回执查核

```dart
class BusinessOperationReceipt {
  const BusinessOperationReceipt({
    required this.operationId,
    required this.moduleId,
    required this.applied,
    this.toolId,
    this.resultFingerprint, // 与写入时 arguments/scope 绑定摘要；换参重放拒绝
    this.resultData = const {},
  });
  final String operationId, moduleId;
  final bool applied;
  final String? toolId, resultFingerprint;
  final Map<String, Object?> resultData;
}

/// features: ModuleFeature.businessReceipts
/// 只读；不得触发领域写入或审批。
abstract interface class BusinessReceiptLookup {
  /// null = 未见过该 operation_id（与「已应用到不同参数」区分由实现抛/返回拒绝对象）。
  Future<BusinessOperationReceipt?> lookupBusinessReceipt(String operationId);
}
```

询价现状：业务回执在模块库 `meta` 键 `reg4c:{operation_id}`（`inquiry_record_tools.dart:400-413`），仅在**写工具事务内**查找；宿主恢复路径（CR-2 §5）需要在不确定时经此接口只读查核，而不再次 `invoke`。

导入侧已有 `ImportCapable.receipt` / `import_intents`，**不要混用**：写卡业务 `operation_id` ≠ 导入 `operation_id`（GB-3 已强调三套日志勿混；此处同类）。

**旧模块退路**：无查找能力 → 恢复只信宿主 `tool_invocation_receipts`；对不上则「结果待核实」，禁止换 `operation_id` 重试（A46–A48）。

### 1.6 与现有可选能力的关系

| 现有 | 关系 |
|---|---|
| `ModuleOntology` | 字段 Kind/敏感度/关系只读真相；**不**表达「本操作可写哪些」 |
| `ActionSpec.tool` | 动作→工具映射；写卡宿主仍用 `UiBusinessAction` 绑 toolId（CR-2 §5） |
| `ImportCapable.receipt` | 仅导入；不实现写卡查核 |
| `PublishChecks` | 数据中心检查，非提交前表单校验 |
| `ResultRenderers` | 对话内展示，非校验 |

`ModuleFeature` 增量：

```dart
enum ModuleFeature {
  importPipeline,
  exchange,
  objectPages,
  publishChecks,
  resultRenderers,
  writeForms,        // 新增
  businessReceipts,  // 新增
}
```

---

## 2. 询价模块落地：文件、改动量、复用

### 2.1 建议改动面（实现时；本文不改代码）

| 区域 | 文件（现状路径） | 大致改动 | 复用 |
|---|---|---|---|
| 契约 | `muyon_module_api` 上表新文件 + `ModuleFeature` | 小（~150–250 行类型 + 测试） | 同 `optional_capabilities` 模式 |
| 可写面 | 今天私有 `_allowedFields` / `_protectedFields` / `_quotationFields` 在 **宿主** `inquiry_record_tools.dart:20-40` | 迁到询价适配或 `supplier_core` 声明，供模块 `writeForms` 与工具 preflight **同源** | 本体 `ontology[type].fields`；报价白名单五字段；保护字段集合 |
| 参数模式 | `_recordSchema` 跨类型字段并集（`:74-135`） | 写卡宿主按 `writeFormFor(type)` 生成**单类型** schema；工具目录可暂留并集但 preflight 已按类型收紧（`:142-148`） | REG-4c preflight |
| 完整校验 | `validatePayload`（`quotation.dart:10-26`）+ `values.dart` 的 `invalid` → `FormatException` | 见 §2.2；工具执行路径仍可先包一层 | `payloadFields`、实体 `fromJson` |
| 版本冲突 | `inquiry_record_tools.dart:422-423` | 改为 `failed` + `WriteConflict` data | 现有 `expected_version` |
| 业务回执 | 同文件 `reg4c:` meta 读写 | 抽只读 `lookup` 实现 `BusinessReceiptLookup`；**写路径仍同事务插入** | REG-4c 参数/范围指纹 |
| 适配声明 | `apps/muyon/lib/app/adapters/inquiry_module.dart`、`coverage.dart` | `features` 增加两项；runtime/`activate` 暴露能力 | 现有 `inquiryOntology` |
| 覆盖清单 | `coverage.dart` 已有 `inquiry.create_record` 等 | 校验/查核不是新业务操作；可选加「写卡门面」条目待覆盖任务 | REG-4c 四写工具 |

粗量级（推测）：契约 + 询价声明/包装 **中**（约 1 个小 PR 契约、1 个 PR 询价适配与工具对齐）；`validatePayload` 多错误收集若做彻底则为 **中大**（触及全部实体 `fromJson`）——故首版建议 §2.2 的包装策略。

### 2.2 `validatePayload`：多错误的最小办法

**现状**：`invalid(field, reason)` → `throw FormatException('$field: $reason')`（`values.dart:3-4`）；`validatePayload` 经各实体 `fromJson` fail-fast；工具在事务内调用（`inquiry_record_tools.dart:429-442`）。

**首版推荐（假设 CR-2 D11）**：

1. **不改**实体 `fromJson` 内核与现有测试语义。
2. 新增 `WriteFormCapable.validateDraft` 的询价实现：
   - 先按 `writeForms` 白名单拒未知/保护字段（可一次收集全部非法键）；
   - 再对「基线 ∪ 改动」调用现有 `validatePayload`；捕获 **一条** `FormatException`，解析 `field: reason` 前缀（格式由本包自己抛出，属稳定约定）填入 `FieldIssue`；
   - 表单级错误（空更新、创建缺必填且无默认、整卡阻断）直接 `formBlocked`。
3. 宿主写卡 UI：用户修正后再次 `validateDraft`，从而「逐次发现」其余错误。
4. 执行事务内仍调用同一 `validatePayload`（CR-2「执行时同一校验器」）。

**为什么首版不改实体层收集器**：11 类实体 + 嵌套 `price_tiers` / `attributes` 全面改成错误列表会牵动 `store.save`、导入、Excel、Hub 等所有调用点；收益对写卡首版（D11 允许逐次）不成比例。若日后要「一次列出全部」（否决 D11 推荐），再引入 `ValidationSink` / `collecting` 模式并单开任务。

**风险**：`FormatException.message` 解析依赖 `'$field: $reason'` 约定；少数 `invalid('payload', …)` 或无冒号消息须落 `formBlocked` 或 `fieldPath='_form'`。须加契约测试钉死格式。

### 2.3 关系写入约束（询价）

静态可见：`links` + `_checkDataScope` 要求新引用在选定范围（`inquiry_record_tools.dart:279-286`）；inquiry 的 `item_ids` 另查项目归属（`:444-452`）。  
`writeForms.relations` 应声明：哪些 `RelationSpec` 允许经通用 `update` 改、是否必须完整 `refList`、是否禁止把解除关联当成 `delete_record`（CR-2 A20）。  
授标/合并/附件字段保持 `_protectedFields` / 人工页（CR-2 §7、D9 推荐）。

---

## 3. 科研模块对应关系

依据 GB-2：科研**无**统一 `save/delete/restore` 与统一行版本；并发靠 `contentDigest` / `revisionRef` + `requireCurrent`。本体 `versioned: true` 仅 task/run/card（`module_declarations.dart`）；project/document/entry/note 等为 `versioned: false`。

| 写卡契约能力 | 能否套用 | 说明 |
|---|---|---|
| `writeForms` 声明可写字段 | **部分** | 仅已/将开放的具名工具面（如 `save_note`、`set_note_entry`、`project.save`、`confirm_binding`）；不要伪造统一 CRUD 四操作 |
| `WriteFormOp.create/update/...` | **不直接套** | 映射到具名工具（`research.save_note` 等），`ObjectWriteForm.humanOnlyReason` 标「无通用 update」 |
| `expectedVersion` int | **不适用**为主 | 用 `expectedContentDigest` / `expected_revision`（GB-2 task.save）；`WriteDraft` 已留字段 |
| `validateDraft` | **可套用形状** | 各工具各自校验；实现可委托现有 Store `checkedObject` / `requireCurrent`；无单一 `validatePayload` |
| 结构化冲突 | **可套用** | `error_code: digest_mismatch` / `revision_mismatch`，`current_version` 放 digest 或 revisionRef 字符串 |
| `BusinessReceiptLookup` | **视工具是否写业务 operation_id** | 现有科研写工具回执形态未能在本任务内与 reg4c 逐字段对齐（**未能静态确认**是否已有等价 meta 键）；若仅有宿主 `tool_invocation_receipts`，可暂不声明 `businessReceipts` |
| 批量原子写卡 | **不适用首版** | 无同事务多对象通用 save；CR-2 D2 未具备前只预览/逐项 |
| `binding.insert` | **不开放** | GB-2：保持 deferred |

结论：科研**先**完成 REG-3d/3e 具名工具与门面；写卡契约在科研侧以「可选实现 + 多数类型 humanOnly」接入，**不以**询价通用四工具为模板强行对齐。

---

## 4. 与 ADR-0004 的关系与待拍板

### 4.1 ADR

| 选项 | 建议 |
|---|---|
| 新开 ADR-0006「写卡与表单校验」 | **不急**；能力仍属模块契约 v2 可选面 |
| **修订 ADR-0004** | **推荐**：§4.5 表增 `WriteFormCapable` / `BusinessReceiptLookup`；§4.3 注明本体不表达可写面；§9/合规套件增「声明 writeForms 则必须实现 validateDraft」交叉检查 |
| 仅 CR-2 / GB-5 评审文档 | 可开干 API 片，但合入 develop 前应有 ADR 修订或明确「实验性可选接口」标注 |

修订幅度：additive，不改 v1，不放宽 ADR-0002。

### 4.2 需要用户拍板的点

**继承 CR-2（推荐假设已用于本设计）**

| 编号 | 事项 | 本设计假设 |
|---|---|---|
| D1 | 写卡是否进同一 UIPlan 树 | 宿主固定内容块 |
| D2 | 批量失败语义 | 原子批量；未具备前不宣称 |
| D3 | 批量条数上限 | 50，取更严者 |
| D4 | 逐次确认 vs 已有授权 | 沿用 ADR-0002；写卡首版不新增长期授权入口 |
| D5 | personal/commercial 卡内显露 | 允许本地显式，默认遮盖 |
| D6 | object 可编辑 | 首版只读 |
| D7 | 字段分组 | 本体序 + 宿主固定折叠 |
| D8 | 新建再关联 | 两次确认 |
| D9 | 报价删/恢复 | 人工页 |
| D10 | 敏感度审查为写卡前提 | 是；新字段未审按 unreviewed |
| D11 | 一次列出全部校验错误 | 先稳定定位；允许逐次发现 |

**本设计新增待拍板**

| 编号 | 事项 | 推荐 |
|---|---|---|
| W1 | 可写面声明放模块 API 还是仅留宿主私有 `_allowedFields` | **进 module_api**（否则「插件不更新也能随本体演进」不成立——插件必须能自声明） |
| W2 | `validatePayload` 首版是否改为收集多错 | **否**；用 `validateDraft` 包装 + 逐次发现（D11） |
| W3 | 冲突是否新 `ToolCallStatus.conflict` | **否**；保持 `failed` + 受信 `data` |
| W4 | 业务回执查找是否独立 `ModuleFeature` | **是**（与 import receipt 分离） |
| W5 | 通用写工具参数 schema 是否改为按类型拆工具 | 首版**可保持**四工具 + 类型枚举；写卡 UI 按单类型生成控件。拆工具另开任务 |
| W6 | 科研是否必须实现 `writeForms` 才算 v2 合规 | **否**；可选；无声明则不出科研通用写卡 |

### 4.3 背景更正（拆分口径，非本任务交付）

用户更正：`agent_dispatch` / `agent_model_turn` 拆分须用**同库私有扩展**，**不用** mixin（GROK-10 实测 mixin 会循环继承）。本 GB-5 不涉及该拆分；若后续写卡接线改动这两个文件，按私有扩展口径，不引入 mixin。

---

## 5. 可独立实现与审查的任务片

### 片 A — `module_api` 写卡契约骨架

- **范围**：`write_forms.dart`、`business_receipts.dart`（或合并）、`ModuleFeature` 两枚举、export、契约单测（冻结 Map、features 交叉说明）。
- **依赖**：无；可先于询价。
- **验收拒绝路径**：
  - 声明 `writeForms` 但 runtime `is! WriteFormCapable` → 注册/合规失败（或宿主拒绝激活写卡特征）。
  - 未声明特征时宿主调用 `validateDraft` / `lookupBusinessReceipt` → 不得进入（测试钉「跳过/退路」）。

### 片 B — 询价 `WriteFormCapable`（可写面 + validateDraft 包装）

- **范围**：从 `inquiry_record_tools` 抽出与工具同源的 `ObjectWriteForm` 表；实现 `validateDraft`（白名单收集 + 一次 `validatePayload`）；适配 `features`。
- **依赖**：片 A。
- **验收拒绝路径**：
  - 本体有、白名单无 → `validateDraft` 报 `unknown_field`，且不调用写工具（A02）。
  - 保护字段 / 报价价格字段 → 拒绝（对齐现 preflight）。
  - 空 `values` 更新 → formBlocked（A07）。
  - 非法十进制 / 未知枚举 → `FieldIssue.fieldPath` 稳定（A09–A11）。

### 片 C — 结构化冲突（reg4c 执行路径）

- **范围**：`expected_version` / scope / referencing 冲突返回 `failed` + `error_code`/`current_version`；不写 `reg4c:` 行。
- **依赖**：片 A 的 `WriteConflict` 约定即可；可与 B 并行。
- **验收拒绝路径**：
  - 陈旧 `expected_version` → `data.error_code == version_conflict` 且含 `current_version`；库版本不变（扩展现有 stale 测试）。
  - 冲突后复用旧审批 / 旧 operation 参数 → 拒绝（A28）；无强制保存入口。
  - 宿主解析中文 summary 的测试**不得**作为唯一分支依据。

### 片 D — `BusinessReceiptLookup`（询价 reg4c 只读）

- **范围**：只读读 `meta[reg4c:…]`；参数/范围指纹不一致返回明确「reuse mismatch」（非 null-applied）；无副作用。
- **依赖**：片 A；与 C 弱相关。
- **验收拒绝路径**：
  - 未知 `operation_id` → `null` → 恢复 UI「结果待核实」，禁止自动换 ID 重发（A47）。
  - 同 ID 不同 arguments/scope → 查找失败或非 applied，不得当成成功（A46）。
  - lookup 实现内不得调用 `store.save`（静态/测试双钉）。

### 片 E — 写卡宿主接线（超出纯契约，列依赖供排期）

- **范围**：按本体 ∩ writeForms 生成卡；确认前 `validateDraft`；确认后经现有写工具 + 审批；恢复走片 D。
- **依赖**：A–D、CR-2 D1/D4/D11 拍板、SN-3/流式退路（CR-2 §5）、业务 action 端口（GB-1 不变量 2 缺口）。
- **验收拒绝路径**：抽 CR-2 A22–A29、A46–A48 各至少一条自动化；卡片侧 A01/A03/A14 可先测宿主筛选器。

**建议合入顺序**：A → C/D（可并行）→ B → E。科研接入另开片 F（可选 `writeForms` 子集），依赖 REG-3d。

---

## 6. 明确不做（本任务已遵守）

- 不改业务/测试代码；不运行 Flutter。
- 不实现写卡 UI、不注册新复合批量工具、不引入 `ToolCallStatus.conflict`。
- 不把 mixin 用作 dispatch/turn 拆分方案。
- 不将导入 `receipt` / `import_intents` 与写卡 `operation_id` 混为同一查找口。

---

## 7. 回报摘要（供 leader）

- **提交**：见本分支 tip（工程师2号按 GB-5 交付）。
- **任务片**：A 契约骨架 · B 询价 writeForms/validateDraft · C 结构化冲突 · D 业务回执只读查找 · E 写卡接线（排期）· F 科研可选接入（后置）。
- **待用户拍板**：CR-2 D1–D11（设计已按推荐假设）+ W1–W6（尤其 W1 进 API、W2 首版不改实体收集器、W3 保持 failed+data）。
