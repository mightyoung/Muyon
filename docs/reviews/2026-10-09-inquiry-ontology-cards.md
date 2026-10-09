# 询价本体驱动业务卡片静态盘点（GROK-5）

日期：2026-10-09 · 任务：[GROK-5](../tasks/GROK-5.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-5-ontology-cards`
方法：只读 `packages/supplier_core/lib/src/ontology.dart`、各实体 `fromJson` / `validatePayload`、`Store` 写路径、`assistant_actions.dart`、宿主 `inquiry_write_tools.dart` 与 `apps/muyon/lib/app/adapters/inquiry_module.dart:308`；**未**改代码、**未**运行 Flutter。
给谁用：REG-4c（按本体通用写工具）、AIUI-9（本体驱动业务卡片）。

敏感度以适配器已落地代码为准（`inquiry_module.dart:278–305`，注释称「ADR-0004 Q7 已采纳划分」）；与 [GROK-3 初稿](2026-10-07-inquiry-sensitivity-draft.md) 有差异处见 §0.2。

---

## 0. 汇总（请先看这里）

| 项 | 结论 |
|---|---|
| 对象类型 | **11**（`entityTypes` / `ontology` 一致）：supplier、contact、product、project、project_item、quotation、inquiry、product_param、spec_request、spec_item、spec_response |
| 字段合计 | **124**（与 GROK-3 计数一致） |
| 校验入口 | 一律 `validatePayload(type, …)`（`quotation.dart:10–26`）→ 各类型 `Type.fromJson`；`Store.save` 在写入前调用（`store.dart:390`） |
| 通用 CRUD Store 成员 | `save` / `delete` / `restore`（软删、`version+1`、记 change_log） |
| 级联写成员（具名） | `mergeInto`/`redirectMerged`；`createInquiry`/`quoteForInquiry`/`award`/`withdrawAward`；`setParam`/`clearParam`/`confirmParams`；`applyRefresh`；技术要求侧 `createSpecRequest`/`saveClauses`/`chooseProduct` 等（REG-4b 清单） |
| 宿主已开放写工具 | **4**：`inquiry.create_inquiry`、`record_quote`、`set_item_qty`、`set_inquiry_status` |
| Folio 自带助手写工具 | **4**：`create_record` / `update_record` / `delete_record` / `restore_record`（仅 7 类实体，见 §2） |
| `agent_tools.dart` | **只读**（describe/search/get/query/…）；**无** create/update/delete |
| 独立对象页（适配器） | `project` / `project_item` / `supplier` / `product` / `inquiry` → `ObjectPageSupport.unbound()`；其余 `none`（「无独立询价页」） |

### 0.1 各对象类型一句话结论

| 类型 | 一句话 |
|---|---|
| `supplier` | 适合新建/编辑卡；合并重复应留原页（级联改引用）。 |
| `contact` | 适合新建/编辑卡与「挂到供应商」关联卡；至少一种联系方式；敏感度 personal。 |
| `product` | 适合新建/编辑卡；改基准单位且保留换算表会被 `save` 拒绝；合并留原页。 |
| `project` | 适合新建/编辑卡；改币种/含税口径若已有预算行或合同额会被拒绝——影响预算口径。 |
| `project_item` | 适合编辑卡（数量已有写工具）；新建宜与项目页一起；`unit_cost`/`quotation_id` 影响预算与比价采用。 |
| `quotation` | 字段多、规则严；推荐专用录价/定标流程，**不建议**整对象通用新建卡直接暴露全部 32 字段。 |
| `inquiry` | 新建优先沿用 `create_inquiry` 专用工具；状态切换已有写工具；通用编辑适合改标题/截止日期/备注。 |
| `product_param` | 适合参数编辑卡，但应走 `setParam`（派生 id），勿当普通 `save` 新建；Folio 助手写工具**未**覆盖此类型。 |
| `spec_request` | 轻量元数据可新建/编辑卡；条款在 `spec_item`，复杂解析留原页。 |
| `spec_item` | `clauses`/`chosen_snapshot` 结构复杂，**不适合**通用表单卡；定选/条款应留技术要求页或将来专用工具。 |
| `spec_response` | 逐条响应宜专用 UI；通用卡仅适合元数据（日期/备注）。 |

### 0.2 敏感度（代码已落地 vs GROK-3 初稿）

适配器 `_sensitivity`（`inquiry_module.dart:278–305`）：

| 标记 | 字段（代码） |
|---|---|
| `personal`（7） | `contact.name/phone/wechat/email`；`quotation.contact_snapshot`；`quotation.inquirer_name`；`project.leader` |
| `commercial`（10） | `project.customer`、`contract_no`、`contract_amount`、`markup_rate`；`project_item.unit_cost`、`unit_price`；`quotation.price`、`extra_cost`、`deal_price`、`price_tiers` |
| `none` | 其余（含 `supplier.address`） |
| `credential` | 0（本体无） |

与 GROK-3 初稿差异（静态可见）：代码把 `customer`/`contract_no` 标为 `commercial`；**未**把 `supplier.address` 标为 `personal`。卡片遮盖以代码为准。

---

## 1. 逐对象类型盘点

约定列：字段名 · 标签 · Kind · 必填 · 枚举/关联 · 敏感度 · 主要校验（代码位置）。
新建/修改均先过 `validatePayload` → `fromJson`；额外 Store 规则另述。

### 1.1 `supplier` 供应商

**字段（8）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `name` | 名称 | text | 是 | — | none | ≤200，`entities.dart:33` |
| `aliases` | 别名 | textList | 否 | 最多 20×200 | none | `:34` |
| `address` | 地址 | text | 否 | ≤500 | none（代码） | `:35` |
| `categories` | 经营类别 | textList | 否 | 最多 20×100 | none | `:36–41` |
| `notes` | 备注 | text | 否 | ≤2000 | none | `:42` |
| `merged_into` | 已合并到 | ref → supplier | 否 | uuid | none | `_mergedInto`；助手写工具禁止写入（`_protectedFields`） |
| `rating` | 评价 | enumeration | 否 | preferred/caution/disabled | none | `supplierRatings` `:52`；停用报价不算可用 |
| `rating_note` | 评价说明 | text | 否 | ≤500 | none | `:45` |

**校验位置**：`Supplier.fromJson` `entities.dart:24–47`；分发 `quotation.dart:14`。

**Store 写**：`save('supplier', …)` 新建/改；`delete`/`restore` 软删；`mergeInto('supplier', from, into)` 写 `merged_into` 并 `redirectMerged` 级联改引用（contact/quotation/inquiry.supplier_ids 等）。修订号：每次 save/delete/restore `version+1`。

**建议卡片**：新建 · 编辑。关联卡：从报价/询价选供应商。  
**不宜卡片**：合并重复（级联面大，ontology `merge_duplicates` 人工动作）→ 留原页。

---

### 1.2 `contact` 联系人

**字段（6）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `supplier_id` | 供应商 | ref → supplier | 是 | uuid | none | `entities.dart:107` |
| `name` | 姓名 | text | 是 | ≤200 | **personal** | 快照规则：`normalizeContactSnapshot` |
| `phone` | 电话 | text | 条件 | ≤100 | **personal** | 电话/微信/邮箱至少一项 `:86–89` |
| `wechat` | 微信 | text | 条件 | ≤100 | **personal** | 同上 |
| `email` | 邮箱 | text | 条件 | ≤254 | **personal** | 同上 |
| `notes` | 备注 | text | 否 | ≤2000 | none | |

**校验位置**：`Contact.fromJson` `entities.dart:104–113`。报价绑定时另有 `Quotation.validateContact`（`quotation.dart:330`）。

**Store 写**：`save`/`delete`/`restore`。无独立合并。删除联系人：软删；已绑报价的 `contact_id`/快照**不**自动清（未能静态确认页面是否拦截删除）。

**建议卡片**：新建 · 编辑 · 关联（挂到供应商）。无独立页（适配器 `page: none`），卡片价值高。  
**不宜卡片**：无。

---

### 1.3 `product` 物料

**字段（12）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `name` | 名称 | text | 是 | ≤200 | none | `entities.dart:142` |
| `unit` | 单位 | text | 是 | ≤50 | none | 改单位须同步处理换算，`store.dart:423–432` |
| `brand`/`model` | 品牌/型号 | text | 否 | ≤200 | none | |
| `specification` | 规格说明 | text | 否 | ≤1000 | none | |
| `category` | 类别 | text | 否 | ≤100 | none | |
| `notes` | 备注 | text | 否 | ≤2000 | none | |
| `merged_into` | 已合并到 | ref → product | 否 | | none | 受保护字段 |
| `attributes` | 关键属性 | object | 否 | ≤12 项，键≤30 值≤100 | none | `_attributes` |
| `unit_conversions` | 报价单位换算 | object | 否 | ≤50；因子正十进制 | none | 影响比价单位折算 |
| `spec_class` | 参数模板 | text | 否 | 字典代码正则 | none | `_specClass` |
| `source_attachment_ids` | 物料来源 | refList | 否 | ≤8 uuid | none | 受保护；附件内容不经工具 |

**校验位置**：`Product.fromJson` `entities.dart:137–170`。

**Store 写**：`save`/`delete`/`restore`；`mergeInto('product', …)` 级联 quotation/project_item 等引用。参数子记录用 `setParam`（派生 id），非本对象字段。

**建议卡片**：新建 · 编辑。关联卡：预算行/报价选物料。  
**不宜卡片**：合并；大量附件管理；参数批量确认（`confirmParams`）→ 物料参数页。

---

### 1.4 `project` 项目

**字段（16）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `code` | 编号 | text | 是 | ≤50 | none | `project.dart:70` |
| `name` | 名称 | text | 是 | ≤200 | none | |
| `status` | 状态 | enumeration | 是 | planning/active/done/cancelled | none | |
| `type` | 类型 | enumeration | 否 | market/internal | none | |
| `level` | 级别 | enumeration | 否 | A/B/C | none | |
| `customer` | 客户 | text | 否 | ≤200 | **commercial** | 代码落地 |
| `contract_no` | 合同号 | text | 否 | ≤100 | **commercial** | 代码落地 |
| `contract_amount` | 合同金额 | decimal | 否 | 十进制文本 | **commercial** | 成本达 90% 提示（规则 `budget`） |
| `department` | 部门 | text | 否 | ≤100 | none | |
| `leader` | 负责人 | text | 否 | ≤100 | **personal** | |
| `start_date`/`end_date` | 日期 | date | 否 | end≥start | none | `:59–60` |
| `currency` | 币种 | text | 是 | `^[A-Z]{3}$` | none | 改口径受限 `store.dart:407–421` |
| `tax_mode` | 含税口径 | enumeration | 是 | included/excluded | none | 同上；决定可选报价 |
| `markup_rate` | 加价率 | decimal | 是 | ≤1000% | **commercial** | 未填销售价时推算 |
| `notes` | 备注 | text | 否 | ≤2000 | none | |

**校验位置**：`Project.fromJson` `project.dart:47–90`。

**Store 写**：`save`/`delete`/`restore`。有预算行或合同额时禁止改 `currency`/`tax_mode`。复制项目等见 `Budgets`（GROK-2 清单）。

**建议卡片**：新建 · 编辑（遮盖 commercial/personal）。  
**不宜卡片**：整库交换/加密导出；「按最优价刷新」整项目（`refreshPlan`/`applyRefresh`）→ 原页或专用工具。

---

### 1.5 `project_item` 预算行

**字段（11）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `project_id` | 项目 | ref → project | 是 | | none | |
| `category` | 成本类别 | enumeration | 是 | material/outsourcing/labor/overhead/other | none | 非 material 不可挂 product |
| `product_id` | 物料 | ref → product | 否 | 仅 material | none | |
| `name` | 名称 | text | 条件 | 无 product 时必填 | none | |
| `qty` | 数量 | decimal | 是 | 正 | none | 已有 `set_item_qty` |
| `unit` | 单位 | text | 是 | ≤50 | none | |
| `quotation_id` | 采用的报价 | ref → quotation | 否 | 须有 product | none | 成本快照来源 |
| `unit_cost` | 成本单价 | decimal | 是 | | **commercial** | 报价变不自动改 |
| `unit_price` | 销售单价 | decimal | 否 | 空则用加价率 | **commercial** | |
| `requirement` | 技术要求 | text | 否 | ≤2000 | none | |
| `notes` | 备注 | text | 否 | ≤2000 | none | |

**校验位置**：`ProjectItem.fromJson` `project.dart:111–152`；`save` 另有 `_checkItem`（引用一致性）。

**Store 写**：`save`/`delete`/`restore`；`award(..., itemId:)` 会写回 `quotation_id`/`unit_cost`/`product_id`；`applyRefresh` 批量改 `unit_cost`。

**建议卡片**：编辑（尤其 qty、requirement）；新建可与项目关联卡组合。  
**不宜卡片**：定标写回、按最优价刷新 → 比价/预算页。

---

### 1.6 `quotation` 报价

**字段（32）** — 摘要按组；完整 ontology 见 `ontology.dart:325–477`。

| 组 | 字段 | 敏感度 | 要点 |
|---|---|---|---|
| 身份 | `supplier_id`*、`product_id`* | none | 必填 uuid |
| 价格核心 | `price`*、`currency`*、`tax_mode`*、`unit_snapshot`*、`min_qty`* | price→**commercial** | 比价/可用规则 |
| 联系 | `contact_id`、`contact_snapshot` | snapshot→**personal** | 有 contact 必有快照；编辑清空需 `allowClear` |
| 询价上下文 | `project_id`、`inquirer_name`、`inquiry_*`、`capture_mode`* | inquirer→**personal** | standard 必填项目/询价人/询价日/报价日；不可降级 historical |
| 费用与定标 | `extra_cost`、`deal_price`、`awarded_on`、`award_note`、`price_tiers` | 金额类→**commercial** | 定标必有 deal_price；阶梯≤10 档且 qty 递增 |
| 其它 | `includes`、`warranty_months`、`lead_time_days`、`valid_until`、`quoted_on`、`tax_rate`、`notes`、`inquiry_id`、`attachment_ids`、`price_basis`、`inquiry_location` | none | attachment 受保护；verbal/reference 不进预算最低价 |

**校验位置**：`Quotation.fromJson` `quotation.dart:180–286`；`_scopeAndAward`/`_tiers`；`validateEditFrom`（禁止静默清空）；`Store._checkQuotation`。

**Store 写**：`save`（改价清空需 `allowClear`）；`quoteForInquiry`；`award`/`withdrawAward`（定标可撤回成交字段，预算行不自动回滚——**未能静态确认**撤回后行上 `unit_cost` 是否人工再改）。

**建议卡片**：关联卡（选供应商+物料）；**窄编辑卡**（只改 notes/交期等非价格字段）。录价优先 `record_quote` 或专用表单。  
**不宜卡片**：整对象 32 字段新建卡；定标（级联预算）；历史资料补录（`capture_mode=historical`，ontology 称仅导入路径）→ 原页/导入。

---

### 1.7 `inquiry` 询价单

**字段（7）**

| 字段 | 标签 | Kind | 必填 | 枚举/关联 | 敏感度 | 校验要点 |
|---|---|---|---|---|---|---|
| `project_id` | 项目 | ref → project | 是 | | none | |
| `title` | 标题 | text | 是 | ≤200 | none | |
| `item_ids` | 预算行 | refList → project_item | 是 | ≤500 | none | 须属同一项目（助手/写工具再检） |
| `supplier_ids` | 供应商 | refList → supplier | 是 | ≤50 | none | |
| `due_date` | 截止日期 | date | 否 | | none | |
| `status` | 状态 | enumeration | 是 | open/closed | none | 已有 `set_inquiry_status` |
| `notes` | 备注 | text | 否 | ≤2000 | none | |

**校验位置**：`Inquiry.fromJson` `inquiry.dart:30–45`。业务创建：`Store.createInquiry` `inquiries.dart:143`（固定 `status=open`）。

**建议卡片**：新建 → 映射到已有 `inquiry.create_inquiry`（勿另造绕过行归属检查的通用 create）；编辑（title/due_date/notes）；关联（增删供应商/行——若开放须带 from_* 乐观锁）。  
**不宜卡片**：Excel 导出发给供应商、设备交换。

---

### 1.8 `product_param` 物料参数

**字段（9）**：`product_id`*、`property`*（字典码）、`value`*（按类型 object）、`cond`、`source`*（manual/rule/ai/import/decoder）、`evidence`、`attachment_id`、`confirmed`*、`dict_version`*。敏感度均为 none（代码）。

**校验位置**：`ProductParam.fromJson` `product_params.dart:41–79`（已知属性走 `normalizeParamValue`）。

**Store 写**：优先 `setParam` / `clearParam` / `confirmParams`（id=`paramRecordId(product,property)`）；裸 `save` 可能绕过派生 id 约定——通用工具应调 `setParam`。

**Folio 助手**：`_types` **不含** `product_param`（`assistant_actions.dart:108–116`）。

**建议卡片**：编辑/确认参数（单参数卡）。  
**不宜卡片**：AI/规则批量抽取应用（plan/apply 两步，REG-4b）→ 原页。

---

### 1.9 `spec_request` 技术要求

**字段（5）**：`project_id`、`title`*、`source_name`、`dict_version`*、`notes`。校验 `spec_request.dart:143–157`。

**Store 写**：`save`；具名 `createSpecRequest` 等（REG-4b）。助手 `_types` 不含。

**建议卡片**：新建/编辑元数据。  
**不宜卡片**：从文件智能解析整份要求 → `smart_import`/原页。

---

### 1.10 `spec_item` 需求项

**字段（12）**：含复杂 `clauses`（≤300）、`chosen_snapshot`。校验 `SpecItem.fromJson` / `SpecClause.fromJson` `spec_request.dart:76+`。

**建议卡片**：**不适合**通用表单卡（嵌套条款+约束+定选快照）。可做关联卡（绑预算行/定选物料）若提供专用工具。  
**应留原页**：条款编辑、定选、匹配物料。

---

### 1.11 `spec_response` 技术响应

**字段（6）**：`item_id`*、`supplier_id`*、`inquiry_id`、`rows`*（≤300）、`received_on`、`notes`。校验 `spec_response.dart:47–78`。

**建议卡片**：不适合整表通用卡；元数据窄编辑可做。  
**应留原页**：逐条偏离填写 / `planSpecResponses`·`applySpecResponses`。

---

## 2. REG-4c 通用写工具草拟

依据设计稿 §4.4 与 ADR-0004：卡片提交走插件写工具；复用 `validatePayload`；带修订号/期望旧值；覆盖清单登记。现有 4 个专用写工具**保留**。

### 2.1 建议新增（宿主 `inquiry.*`）

| 工具 ID | 输入模式（按本体） | 效应 | 调用 Store | 校验 |
|---|---|---|---|---|
| `inquiry.create_record` | `type`∈可开放类型；`values`：该类型字段子集（必填由本体+fromJson 强制） | 新建一条；返回 id+version | `store.save(type, values, newId: …)`；`product_param` → `setParam` | `validatePayload`；禁止 `_protectedFields`；inquiry 行须属 project（同 `assistant_actions._checkInquiry`） |
| `inquiry.update_record` | `type`、`id`、`values`（仅改动字段）、`expected_version`（或字段级 `from_*`） | 修改；版本不符拒绝 | `save(..., id:, allowClear: 按预览)`；param → `setParam` | 同上 + 乐观锁；quotation 清空规则 |
| `inquiry.delete_record` | `type`、`id`、`expected_version` | 软删 | `store.delete` | 存在且未删；预览列出 `referencesTo` |
| `inquiry.restore_record` | `type`、`id`、`expected_version` | 恢复 | `store.restore` | 须已删；引用仍有效 |

**首批建议开放的 `type`（与 Folio 助手对齐）**：`supplier`、`contact`、`product`、`project`、`project_item`、`inquiry`、`quotation`（quotation 建议再加「字段白名单」或强制走 `record_quote`/`award`）。  
**延后**：`product_param`（用 `setParam` 封装成 `inquiry.set_param`）、`spec_*`（结构复杂，标 `deferred` 或 humanOnly 直至专用工具）。

**仍建议专用（不并入通用 CRUD）**：

| 工具 | 理由 |
|---|---|
| 已有 `create_inquiry` / `record_quote` / `set_item_qty` / `set_inquiry_status` | 已带 from_* 与范围校验 |
| 未来 `inquiry.award` / `withdraw_award` | 级联预算；不可用通用 update 拼 `awarded_on` |
| 未来 `inquiry.merge_into` | 仅 supplier/product；级联 redirect |
| 未来 `inquiry.apply_refresh` | 计划/应用两步 |

### 2.2 与 Folio 自带助手工具的对应

| Folio（`assistant_actions.dart`） | 建议宿主工具 | 差异 |
|---|---|---|
| `create_record` | `inquiry.create_record` | 宿主审批+回执+范围；禁 `bypass` 裸写（REG-4c / Q12） |
| `update_record` | `inquiry.update_record` | 增加 `expected_version`；与现写工具 from_* 风格一致 |
| `delete_record` | `inquiry.delete_record` | 同上 |
| `restore_record` | `inquiry.restore_record` | 同上 |
| （无，仅页面） | 保留 4 个 `inquiry_write_tools` | Folio 助手无对等专用名 |
| `agent_tools.dart` 只读集 | 已映射为 `inquiry.describe` 等读工具 | 无写 |

Folio `_protectedFields`：`merged_into`、`attachment_ids`、`source_attachment_ids`、`capture_mode` —— 通用写工具应同样禁止或仅 humanOnly。  
Folio `_types` 仅 7 类；`product_param`/`spec_*` 不在助手写工具内。

### 2.3 卡片类型 ↔ 工具

| 卡片 | 条件 | 工具 |
|---|---|---|
| 新建卡 | 类型已注册写工具且非 deferred | `create_record` 或专用 `create_inquiry` |
| 编辑卡 | 同上；带 version | `update_record` / `set_item_qty` / `set_inquiry_status` |
| 关联卡 | 关系在 `links`；写一侧 ref 字段 | `update_record`（改 ref）或就地 `create_record` 再关联 |
| 批量卡 | 导入审阅等 | REG-4b plan/apply 或 ImportCapable；**非**通用 CRUD |

覆盖清单标不开放 → 卡片文案「请在原页面操作」并链到 `ObjectPageSupport` 入口（五类 unbound 页）。

---

## 3. 风险：比价 / 定标 / 预算口径与不可逆

### 3.1 写入会影响比价的字段/操作

| 对象.字段或操作 | 影响 |
|---|---|
| `quotation.price` / `extra_cost` / `price_tiers` / `deal_price` | 有效单价与矩阵最低价（规则 `effective_price`/`deal_price`） |
| `quotation.tax_mode` / `currency` / `unit_snapshot` / `min_qty` / `valid_until` / `quoted_on` / `price_basis` | 可否同组比较、是否「可用」 |
| `quotation.awarded_on`（`award`） | 定标优先；成交价覆盖报价单价 |
| `supplier.rating=disabled` | 报价不算可用/最低 |
| `product.unit` / `unit_conversions` | 单位折算；缺规则不可跨单位比 |
| `project.currency` / `tax_mode` | 项目选价口径；`quote_options` 过滤 |

### 3.2 写入会影响预算口径的字段/操作

| 对象.字段或操作 | 影响 |
|---|---|
| `project.markup_rate` / `contract_amount` | 销售价推算、合同 90% 提示 |
| `project_item.qty` / `unit_cost` / `unit_price` / `quotation_id` | 行金额与提示（`needs_inquiry` 等） |
| `award(..., itemId:)` | 写回成本单价与采用报价 |
| `applyRefresh` | 批量把行成本改为当前最优可用价 |
| 禁止：有预算时改项目币种/含税口径 | `store.dart:407–421` |

### 3.3 相对不可逆或高风险操作

| 操作 | 可恢复性（静态） | 建议 |
|---|---|---|
| `delete` | 软删，可 `restore` | 可开放，须确认+列引用 |
| `mergeInto` | 保留行+`merged_into`；`redirectMerged` 改大量引用；拆除合并路径有限 | **危险**；卡片勿做；humanOnly 或强确认 |
| `award` | `withdrawAward` 清成交字段；**预算行 unit_cost 是否自动回滚未能静态确认** | 专用工具+确认；勿通用 update |
| 改 `capture_mode` standard→historical | `validateEditFrom` 禁止 | 工具禁止 |
| 清空报价已有字段 | 需 `allowClear`/明示 | 确认卡展示清空项 |
| 交换/加密覆盖/文件夹同步 | 整库级 | 已有 ADR：不开放为普通写工具 |
| 附件二进制 | 不经助手工具 | 不进卡片 |

---

## 4. 未能静态确认

1. 撤回定标后，已被写回的 `project_item.unit_cost` / `quotation_id` 是否由 UI 自动恢复旧值。  
2. 删除仍被报价引用的 `contact` 时，页面是否拦截（Store 层未见拒删）。  
3. REG-4c 最终工具命名是 `create_record` 还是 `ontology_create` / 分类型 `create_supplier`——本文按与 Folio 对齐的 `inquiry.create_record` 草拟，实施以任务书为准。  
4. AIUI-9 卡片是否首期包含 `spec_*`——本文建议首期不做通用卡。

---

## 5. 建议工具清单（给 REG-4c / AIUI-9）

**保留**：`inquiry.create_inquiry`、`inquiry.record_quote`、`inquiry.set_item_qty`、`inquiry.set_inquiry_status`。

**新增（通用 CRUD）**：`inquiry.create_record`、`inquiry.update_record`、`inquiry.delete_record`、`inquiry.restore_record`（首批 7 类型；保护字段同 Folio；强制 version/from_*）。

**后续专用**：`inquiry.set_param`、`inquiry.award`、`inquiry.withdraw_award`、`inquiry.merge_into`（慎）、`inquiry.apply_refresh`（两步）。

**卡片首期**：supplier / contact / product / project / project_item / inquiry（新建走专用）编辑与关联；quotation 仅窄字段或录价专用；spec_* 与定标/合并留原页。
