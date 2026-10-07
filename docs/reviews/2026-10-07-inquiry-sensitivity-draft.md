# 询价敏感字段划分初稿（ADR-0004 Q7 / GROK-3）

日期：2026-10-07 · 任务：[GROK-3](../tasks/GROK-3.md) · 执行：工程师2号（grokbot）· 分支：`task/grok-3-sensitivity-draft` · 方法：只读 `packages/supplier_core/lib/src/ontology.dart` 及外传路径，**未**改代码、**未**运行 Flutter · 依据：[ADR-0004](../adr/0004-module-contract-v2.md) §4.3 / §12.1 Q7（用户已采纳词表与初稿方向；**最终字段划分仍须用户确认**，先于 REG-4b / DC-3）。

词表（四选一，不得留 `unreviewed`）：

| 标记 | 含义（给非开发者） |
|---|---|
| `none` | 已审阅：不敏感，助手与数据中心可照常展示、同步 |
| `personal` | 个人联系信息或可识别到具体人的信息（电话、邮箱、地址、姓名等） |
| `commercial` | 商业机密类金额与定价（单价、成本、加价/毛利、合同额、成交价等） |
| `credential` | 访问密钥、令牌一类，绝不当普通字段外传 |

Q7 初稿方向：**联系人电话 / 邮箱 / 地址 → `personal`；单价、成本、毛利、合同额、成交价 → `commercial`；其余 → `none`。** 本表在此基础上做逐字段建议；「拿不准」单独列出，请用户拍板。

---

## 0. 汇总（请先看这里）

| 建议敏感度 | 字段数 | 说明 |
|---|---:|---|
| `none` | 108 | 按 Q7「其余为 none」；其中部分见下方「待拍板」，暂按 none 落地 |
| `personal` | 8 | `contact` 的姓名/电话/微信/邮箱；`quotation.contact_snapshot`；`supplier.address`（按 Q7）；`project.leader`；`quotation.inquirer_name` |
| `commercial` | 8 | 单价、成交价、附加费、阶梯价、合同金额、加价率、成本单价、销售单价 |
| `credential` | 0 | **询价本体 `ontology.dart` 内无凭据字段**（公司资料中心令牌见 U10，不计入） |
| **合计（本体字段）** | **124** | 11 个对象类型，见 §1 |

**需要用户拍板的字段 / 事项（详见 §2）**

| # | 对象.字段 | 两种候选 | 为何拿不准 |
|---|---|---|---|
| U1 | 各类型 `notes`（10 处） | `none` / `personal`（或按内容视为商业） | 自由备注什么都能写 |
| U2 | `supplier.name`、`supplier.aliases` | `none` / `commercial` | 供应商全称是否算商业机密 |
| U3 | `supplier.address` | `personal`（Q7）/ `none` | Q7 写「地址→personal」，但这里是**单位地址**不是私人住址 |
| U4 | `project.customer`、`project.contract_no` | `none` / `commercial` | 客户名、合同号是否对外保密 |
| U5 | `project.leader`、`quotation.inquirer_name` | `personal` / `none` | 是本公司人名，是否按个人隐私遮盖 |
| U6 | `supplier.rating_note`、`quotation.award_note`、`quotation.inquiry_location` | `none` / `personal` 或 `commercial` | 可能夹带人名、地点或议价理由 |
| U7 | `product.source_attachment_ids`、`quotation.attachment_ids`、`product_param.attachment_id` | `none` / 随附件内容 | 本体只有附件 id；附件原件可能含价目表/身份证等 |
| U8 | `product_param.evidence` | `none` / `commercial` | 依据原文偶发含价 |
| U9 | **税号、银行账户** | — | **不在** `ontology.dart` 的 11 类对象字段里；若日后加入，建议默认 `commercial` 或 `credential`（银行账户）并再确认 |
| U10 | **公司资料中心访问令牌** | 必为 `credential` | **不是**询价本体字段；存在设置页 / 系统安全存储（`hub_settings.dart`、`HubClient.token`），不进本表计数 |

拍板前可先按本表「建议」落地；U1～U8 未确认前，合规套件仍须有明确类别（不可 `unreviewed`）。不确定时本任务要求标「待用户确认」。

---

## 1. 逐对象、逐字段建议

每行：`字段名` · 中文标签 · 类型 · **建议敏感度** · 理由 · `ontology.dart:行`。

### 1.1 `supplier` 供应商（8）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `name` | 名称 | 文本 | **待用户确认**（暂记 `none`） | 供应商全称；遮盖则搜供应商、比价标题几乎不可用。见 U2 | `:134` |
| `aliases` | 别名 | 文本列表 | **待用户确认**（暂记 `none`） | 简称/曾用名，与名称同类。见 U2 | `:135` |
| `address` | 地址 | 文本 | **待用户确认**（Q7 倾向 `personal`） | Q7 写地址→personal；此处多为单位地址。见 U3 | `:136` |
| `categories` | 经营类别 | 文本列表 | `none` | 经营品类标签，无联系人/金额 | `:137` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 自由文本。见 U1 | `:138`（`_notes` `:123`） |
| `merged_into` | 已合并到 | 引用 | `none` | 指向保留记录的 id，非隐私内容 | `:139` |
| `rating` | 评价 | 枚举 | `none` | 采购方评级枚举，非金额非联系方式 | `:141` |
| `rating_note` | 评价说明 | 文本 | **待用户确认**（暂记 `none`） | 可能写具体人/商务理由。见 U6 | `:147` |

### 1.2 `contact` 联系人（6）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `supplier_id` | 供应商 | 引用 | `none` | 所属供应商 id | `:151` |
| `name` | 姓名 | 文本 | `personal` | 具体人的姓名，可识别个人 | `:158` |
| `phone` | 电话 | 文本 | `personal` | Q7：联系人电话→personal | `:159` |
| `wechat` | 微信 | 文本 | `personal` | 与电话同类的私人联系方式 | `:160` |
| `email` | 邮箱 | 文本 | `personal` | Q7：邮箱→personal | `:161` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:162` |

### 1.3 `product` 物料（12）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `name` | 名称 | 文本 | `none` | 物料通用名 | `:165` |
| `unit` | 单位 | 文本 | `none` | 计量单位 | `:166` |
| `brand` | 品牌 | 文本 | `none` | 公开品牌信息 | `:167` |
| `model` | 型号 | 文本 | `none` | 型号规格标识 | `:168` |
| `specification` | 规格说明 | 文本 | `none` | 物料自身规格文字 | `:170` |
| `category` | 类别 | 文本 | `none` | 分类标签 | `:175` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:176` |
| `merged_into` | 已合并到 | 引用 | `none` | 合并目标 id | `:177` |
| `attributes` | 关键属性 | 对象 | `none` | 参数名→值，技术属性 | `:179` |
| `unit_conversions` | 报价单位换算 | 对象 | `none` | 单位换算系数，非金额 | `:185` |
| `spec_class` | 参数模板 | 文本 | `none` | 参数字典类别代码 | `:191` |
| `source_attachment_ids` | 物料来源 | 引用列表 | **待用户确认**（暂记 `none`） | 附件 id，非路径；原件内容另议。见 U7 | `:197` |

### 1.4 `project` 项目（16）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `code` | 编号 | 文本 | `none` | 项目编号，内部标识 | `:205` |
| `name` | 名称 | 文本 | `none` | 项目名称 | `:211` |
| `status` | 状态 | 枚举 | `none` | 筹备/进行中等状态 | `:213` |
| `type` | 类型 | 枚举 | `none` | 市场/内部 | `:226` |
| `level` | 级别 | 枚举 | `none` | A/B/C | `:233` |
| `customer` | 客户 | 文本 | **待用户确认**（暂记 `none`） | 客户名是否保密。见 U4 | `:239` |
| `contract_no` | 合同号 | 文本 | **待用户确认**（暂记 `none`） | 合同标识。见 U4 | `:240` |
| `contract_amount` | 合同金额 | 十进制文本 | `commercial` | Q7：合同额→commercial | `:242` |
| `department` | 部门 | 文本 | `none` | 组织部门名 | `:247` |
| `leader` | 负责人 | 文本 | **待用户确认**（倾向 `personal`） | 人名。见 U5 | `:248` |
| `start_date` | 开始日期 | 日期 | `none` | 日程 | `:249` |
| `end_date` | 结束日期 | 日期 | `none` | 日程 | `:250` |
| `currency` | 币种 | 文本 | `none` | ISO 币种代码（`_currency`） | `:251`（`:116`） |
| `tax_mode` | 含税口径 | 枚举 | `none` | 含税/不含税口径，非金额本身 | `:253` |
| `markup_rate` | 加价率 | 十进制文本 | `commercial` | Q7：毛利相关；销售价由此推算 | `:261` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:267` |

### 1.5 `project_item` 预算行（11）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `project_id` | 项目 | 引用 | `none` | 所属项目 | `:271` |
| `category` | 成本类别 | 枚举 | `none` | 材料/外包等类别 | `:279` |
| `product_id` | 物料 | 引用 | `none` | 关联物料 | `:293` |
| `name` | 名称 | 文本 | `none` | 行名称（未关联物料时） | `:299` |
| `qty` | 数量 | 十进制文本 | `none` | 数量本身非定价机密 | `:300` |
| `unit` | 单位 | 文本 | `none` | 计量单位 | `:301` |
| `quotation_id` | 采用的报价 | 引用 | `none` | 引用 id；金额在报价对象上 | `:303` |
| `unit_cost` | 成本单价 | 十进制文本 | `commercial` | Q7：成本→commercial | `:310` |
| `unit_price` | 销售单价 | 十进制文本 | `commercial` | 对外销售价，属定价/毛利 | `:316` |
| `requirement` | 技术要求 | 文本 | `none` | 项目对行的技术要求原文 | `:318` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:323` |

### 1.6 `quotation` 报价（32）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `supplier_id` | 供应商 | 引用 | `none` | 供应商 id | `:327` |
| `product_id` | 物料 | 引用 | `none` | 物料 id | `:335` |
| `price` | 单价 | 十进制文本 | `commercial` | Q7：单价→commercial | `:343` |
| `currency` | 币种 | 文本 | `none` | 币种代码 | `:349` |
| `tax_mode` | 含税口径 | 枚举 | `none` | 含税口径枚举 | `:351` |
| `unit_snapshot` | 单位 | 文本 | `none` | 报价时计量单位 | `:359` |
| `min_qty` | 起订量 | 十进制文本 | `none` | 数量门槛，非单价 | `:366` |
| `quoted_on` | 报价日期 | 日期 | `none` | 日期 | `:372` |
| `contact_id` | 联系人 | 引用 | `none` | 引用 id；联系方式在 contact / snapshot | `:373` |
| `contact_snapshot` | 联系人快照 | 对象 | `personal` | 含 `{name, phone, wechat, email}`，与联系人同类 | `:375` |
| `tax_rate` | 税率 | 十进制文本 | `none` | 税率百分数；非成交机密本身 | `:380` |
| `lead_time_days` | 交期（天） | 整数 | `none` | 交期 | `:381` |
| `valid_until` | 有效期至 | 日期 | `none` | 有效期 | `:383` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:388` |
| `project_id` | 项目 | 引用 | `none` | 所属项目 | `:390` |
| `inquiry_location` | 询价地点 | 文本 | **待用户确认**（暂记 `none`） | 可能暴露工作地点。见 U6 | `:396` |
| `inquirer_name` | 询价人 | 文本 | **待用户确认**（倾向 `personal`） | 本公司询价人名。见 U5 | `:397` |
| `inquiry_precision` | 询价时间精度 | 枚举 | `none` | 精度枚举 | `:399` |
| `inquiry_date` | 询价日期 | 日期 | `none` | 日期 | `:409` |
| `inquired_at` | 询价时刻 | 时间点 | `none` | 时刻 | `:410` |
| `inquiry_utc_offset_minutes` | 询价时区 | 整数 | `none` | 时区偏移 | `:412` |
| `capture_mode` | 录入方式 | 枚举 | `none` | 标准/历史补录 | `:418` |
| `includes` | 价格包含 | 文本列表 | `none` | 运费/安装等包含项标签 | `:429` |
| `warranty_months` | 质保（月） | 整数 | `none` | 质保月数 | `:440` |
| `extra_cost` | 附加费用 | 十进制文本 | `commercial` | 整单另收费，进入有效单价 | `:442` |
| `deal_price` | 成交单价 | 十进制文本 | `commercial` | Q7：成交价→commercial | `:447` |
| `awarded_on` | 定标日期 | 日期 | `none` | 定标日期标记 | `:448` |
| `award_note` | 定标说明 | 文本 | **待用户确认**（暂记 `none`） | 可能含议价理由。见 U6 | `:449` |
| `inquiry_id` | 询价单 | 引用 | `none` | 询价单 id | `:451` |
| `attachment_ids` | 附件 | 引用列表 | **待用户确认**（暂记 `none`） | 本体注释：附件内容不通过工具提供；原件仍可能敏感。见 U7 | `:458` |
| `price_basis` | 价格性质 | 枚举 | `none` | 口头/参考价标记 | `:464` |
| `price_tiers` | 阶梯价 | 对象 | `commercial` | `[{min_qty, price}]`，内含单价 | `:471` |

### 1.7 `inquiry` 询价单（7）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `project_id` | 项目 | 引用 | `none` | 所属项目 | `:480` |
| `title` | 标题 | 文本 | `none` | 询价单标题 | `:487` |
| `item_ids` | 询价的预算行 | 引用列表 | `none` | 预算行 id 列表 | `:489` |
| `supplier_ids` | 询价的供应商 | 引用列表 | `none` | 供应商 id 列表 | `:497` |
| `due_date` | 截止日期 | 日期 | `none` | 截止日期 | `:504` |
| `status` | 状态 | 枚举 | `none` | 进行中/已结束 | `:506` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:513` |

### 1.8 `product_param` 物料参数（9）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `product_id` | 物料 | 引用 | `none` | 所属物料 | `:517` |
| `property` | 参数 | 文本 | `none` | 参数字典代码 | `:525` |
| `value` | 取值 | 对象 | `none` | 结构化技术取值 | `:532` |
| `cond` | 条件 | 文本 | `none` | 取值条件说明 | `:540` |
| `source` | 来源 | 枚举 | `none` | 手填/AI 等来源 | `:542` |
| `evidence` | 依据 | 文本 | **待用户确认**（暂记 `none`） | 说明书原文，偶发含价。见 U8 | `:555` |
| `attachment_id` | 依据文件 | 引用 | **待用户确认**（暂记 `none`） | 附件 id。见 U7 | `:556` |
| `confirmed` | 已确认 | 是/否 | `none` | 人工核对标记 | `:558` |
| `dict_version` | 字典版本 | 整数 | `none` | 字典版本号 | `:565` |

### 1.9 `spec_request` 技术要求（5）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `project_id` | 项目 | 引用 | `none` | 所属项目 | `:573` |
| `title` | 标题 | 文本 | `none` | 标题 | `:574` |
| `source_name` | 来源 | 文本 | `none` | 文件名或「粘贴文本」 | `:575` |
| `dict_version` | 字典版本 | 整数 | `none` | 字典版本 | `:576` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:577` |

### 1.10 `spec_item` 需求项（12）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `request_id` | 技术要求 | 引用 | `none` | 所属技术要求 | `:581` |
| `seq` | 序号 | 整数 | `none` | 序号 | `:588` |
| `name` | 设备名称 | 文本 | `none` | 设备名 | `:589` |
| `spec_class` | 设备类别 | 文本 | `none` | 参数字典类别 | `:591` |
| `qty` | 数量 | 十进制文本 | `none` | 数量 | `:596` |
| `unit` | 单位 | 文本 | `none` | 单位 | `:597` |
| `text` | 要求原文 | 文本 | `none` | 技术要求原文 | `:598` |
| `project_item_id` | 预算行 | 引用 | `none` | 关联预算行 | `:600` |
| `clauses` | 条款 | 对象 | `none` | 结构化条款（技术条件） | `:607` |
| `chosen_product_id` | 定选物料 | 引用 | `none` | 定选物料 id | `:614` |
| `chosen_snapshot` | 定选快照 | 对象 | `none` | 逐条响应快照（技术响应，非报价金额） | `:621` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:626` |

### 1.11 `spec_response` 技术响应（6）

| 字段 | 标签 | 类型 | 建议 | 理由 | 引用 |
|---|---|---|---|---|---|
| `item_id` | 需求项 | 引用 | `none` | 需求项 id | `:630` |
| `supplier_id` | 供应商 | 引用 | `none` | 供应商 id | `:638` |
| `inquiry_id` | 询价单 | 引用 | `none` | 询价单 id | `:645` |
| `rows` | 逐条响应 | 对象 | `none` | 保证值/偏离声明（技术），非报价单价 | `:647` |
| `received_on` | 收到日期 | 日期 | `none` | 日期 | `:653` |
| `notes` | 备注 | 文本 | **待用户确认**（暂记 `none`） | 见 U1 | `:654` |

### 1.12 计数核对

| 建议 | 数 | 成员（权威） |
|---|---:|---|
| `personal` | **8** | `contact.name` / `phone` / `wechat` / `email`；`quotation.contact_snapshot`；`supplier.address`（按 Q7）；`project.leader`；`quotation.inquirer_name` |
| `commercial` | **8** | `quotation.price` / `deal_price` / `extra_cost` / `price_tiers`；`project.contract_amount` / `markup_rate`；`project_item.unit_cost` / `unit_price` |
| `none`（含暂记） | **108** | 其余全部（含 §2 待拍板项的暂记默认） |
| `credential` | **0** | 本体无 |
| 合计 | **124** | 与 `_types` 字段数一致 |

按对象类型的字段数：supplier 8、contact 6、product 12、project 16、project_item 11、quotation 32、inquiry 7、product_param 9、spec_request 5、spec_item 12、spec_response 6。

---

## 2. 「拿不准」字段：遮盖 vs 不遮盖的后果

### U1 各类型 `notes`（备注）

出现位置：`supplier` `:138`、`contact` `:162`、`product` `:176`、`project` `:267`、`project_item` `:323`、`quotation` `:388`、`inquiry` `:513`、`spec_request` `:577`、`spec_item` `:626`、`spec_response` `:654`（共用 `_notes` `:123`）。

| 若标为… | 对助手 / 数据中心 | 风险 |
|---|---|---|
| 遮盖（`personal` 或 `commercial`） | 助手回答「备注里写了什么」会缺内容；数据中心同步实例时剔除备注；问数据场景体验变差 | 误伤：大量无害备注也被挡 |
| 不遮盖（`none`） | 助手与导出可原样带走备注全文 | 有人把电话、底价、身份证号写进备注时，审查按「无敏感字段」放行 |

**建议默认 `none`，并在产品文案提醒「别把隐私写进备注」；若用户要求严，可升为 `personal`。待用户确认。**

### U2 `supplier.name` / `supplier.aliases`

| 若遮盖（`commercial`） | 供应商列表、比价、询价单、公司资料发布标题几乎无法展示；助手无法按名称检索 |
| 若不遮盖（`none`） | 供应商名单可随导出/助手外传；一般视为公开商务信息，但部分采购方视供应商关系为机密 |

**建议暂 `none`。待用户确认。**

### U3 `supplier.address`

| 若按 Q7 标 `personal` | 地址在助手回答与数据中心同步中被遮盖/剔除；地图类展示需另议 |
| 若标 `none` | 单位地址随记录外传；泄露面小于私人住址，但仍可能定位办公点 |

**Q7 原文写「地址→personal」。待用户确认：单位地址是否仍按 personal。**

### U4 `project.customer` / `project.contract_no`

| 若遮盖（`commercial`） | 面向客户的报价单导出仍可能需要客户名（`exportQuoteSheet` 会写出客户）；助手少报项目归属 |
| 若不遮盖 | 客户清单与合同号可外传，存在商务关系泄露 |

**建议暂 `none`。待用户确认。**

### U5 `project.leader` / `quotation.inquirer_name`

| 若标 `personal` | 人名在同步与外传审查中按个人隐私处理；内部协作展示需本机 UI 另开 |
| 若标 `none` | 负责人/询价人姓名随项目与报价外传 |

**本初稿倾向 `personal`（计入上文 8 个 personal）。待用户确认是否过严。**

### U6 `rating_note` / `award_note` / `inquiry_location`

| 若遮盖 | 评价说明、定标说明、询价地点助手说不清 |
| 若不遮盖 | 可能带出议价策略、内部评价或地点 |

**建议暂 `none`。待用户确认。**

### U7 附件 id 字段（`source_attachment_ids` / `attachment_ids` / `attachment_id`）

本体只有 id；附件字节在库表 `attachment`（`attachments.dart`），工具侧注明「附件内容不通过工具提供」（`ontology.dart:461`）。

| 若把 id 标敏感 | 几乎无收益（id 本身难读），却干扰「有哪些附件」类问答 |
| 若不标、但附件原件含敏感页 | 导出交换文件会带走附件字节（`attachments.dart` 注释：exchange 携带附件）；Excel/人工导出路径另含业务字段 |

**建议 id 字段暂 `none`；附件二进制的遮盖策略交给导出/交换专项，不在本字段表一次定死。待用户确认。**

### U8 `product_param.evidence`

| 若遮盖 | 助手少了参数依据原文 |
| 若不遮盖 | 偶发从说明书粘进价格句 |

**建议暂 `none`。待用户确认。**

### U9 税号、银行账户

在 `packages/supplier_core/lib/src/ontology.dart` 的 11 个 `ObjectType` 中**未出现**税号、银行账户字段（已用全文检索核对）。若未来加入供应商档案：建议税号→`commercial`，银行账户→`credential` 或 `commercial`，并再走一轮用户确认。

### U10 公司资料中心访问令牌

非本体字段。UI：`packages/inquiry_module/lib/src/features/hub/hub_settings.dart`（地址 + 令牌，令牌进系统安全存储）；运行时：`HubClient.token`（`hub.dart:70,106`，请求头 `Bearer`）。**应视为 `credential`，不得进助手知识库同步，不得进 `describe`/`ontologyCard` 实例。** 本表不计入 124。

---

## 3. 字段之外可能带出敏感信息的地方（只记录，不判定）

下列路径会把业务数据或结构说明送出界面/模型/文件；是否按敏感字段遮盖由后续 REG-4b / DC-3 / 导出策略决定，此处仅登记。

| 路径 | 位置 | 可能带出什么 |
|---|---|---|
| 系统提示中的本体卡片 | `ontologyCard()` `ontology.dart:719-741`；拼进助手提示 `assistant.dart:99` | 全部对象类型的**字段名、中文标签、类型、说明、枚举取值**（无实例数据） |
| 助手工具 `describe` | `agent_tools.dart:330-370` | 无参：类型列表 + 链接 + 规则全文 + 应用内动作文案；有参：该类型 `toJson()`（字段元数据）+ 出入链 + `paths_to` |
| 读工具返回的记录 | `agent_tools.dart` 各 `get`/`search`/比价/预算路径（如 `:305-307`、`:454-535`） | **实例**里的单价、成本、联系人快照等 |
| 客户报价 Excel | `project_export.dart:86-137` `exportQuoteSheet` | 项目名/编号、**客户**、销售单价与金额；设计意图：不含成本、供应商、毛利（`:85`） |
| 成本预算 Excel | `project_export.dart:141+` `exportCostBudget` | **合同金额、加价率、成本单价、供应商名** 等 |
| 询价单 Excel | `inquiries.dart:402+` `exportInquirySheet` | 询价行、含税口径、税率列等（供供应商填写单价） |
| 整库 / 选择导出 | `exchange.dart` `exportTo`；`share.dart` `exportSelection`；`crypto_file.dart` `exportEncryptedTo` | 库内记录 + **附件字节** |
| 文件夹同步 | `folder_sync.dart` | 同上，可加密 |
| 公司资料发布 | hub 发布确认文案（`hub_publish.dart` / `hub_confirmation.dart`） | 选中的供应商/报价完整内容发往中心 |
| MCP / 模型网关令牌 | `mcp_servers_page.dart`、`credential_redaction.dart`、`model_gateway.dart` | 访问令牌（属凭据，已有脱敏专项 P0-S1/S2） |
| 规则文案中的业务口径 | `ontology.dart` `rules` `:683-704` | 经 `describe` / `ontologyCard` 告诉模型如何理解成交价、有效单价等（元数据，非实例） |

---

## 4. 建议落地口径（供用户勾选）

**若用户一键采纳「Q7 + 本初稿已定部分」：**

1. 将上表 **8 个 `personal` + 8 个 `commercial`** 写入敏感标记；其余 108 个标 `none`。  
2. 对 §2 U1–U8：默认保持 `none`（`supplier.address` 已在 personal 组按 Q7），仅把用户勾改的项升格。  
3. U9：本体无字段，无需标记。  
4. U10：公司资料令牌按 `credential` 管理（设置/密钥库），不进入询价 `ModuleOntology` 字段列表。  
5. §3 外传路径：在 REG-4b / DC-3 做「含非 none 字段的实例不同步、导出分类」时对照本表，不在本任务改代码。

**请用户确认：** §0/定稿计数、U1–U8 各项去留、U3 单位地址是否维持 `personal`。

---

## 5. 方法与局限

- 字段全集来自 `ontology.dart` `_types`（`:132-656`），与 `objectGroups`（`:665-669`）十一类一致；行号以本分支文件为准。  
- 未运行 Flutter / 测试；未改任何代码。  
- 「暂记 `none`」≠ 最终决定；合规要求合并前不得残留 `unreviewed`（ADR-0004 §4.3）。  
- 税号/银行账户/中心令牌：本体外事项，已单独说明，避免误以为已覆盖。
