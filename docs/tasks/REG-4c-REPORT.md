# REG-4c 实施与验证回报

独立分支：`task/reg-4c-general-writes`；基线 develop：`7773b7d96bc99f173b57a723d61526fba0df49ff`。草稿 PR：[#31](https://github.com/mightyoung/Muyon/pull/31)。开始前已更新全部远端分支并检查同任务分支/开放 PR，没有重复 active 实现。父任务独占最终审查及合入 develop。

## 工具、范围与回执

4 个宿主工具均为 `ToolEffect.write`、仅 `selectedObjects`、数据模块仅 inquiry；不新增自动批准通道。审批仍由宿主确认卡/原授权策略执行，模型传 operation_id 不构成批准。

| 工具 | 必填输入 |
| --- | --- |
| `inquiry.create_record` | `operation_id`、`type`、`values` |
| `inquiry.update_record` | `operation_id`、`type`、`id`、`expected_version`、`values` |
| `inquiry.delete_record` | `operation_id`、`type`、`id`、`expected_version`、`referencing_records` |
| `inquiry.restore_record` | `operation_id`、`type`、`id`、`expected_version` |

`operation_id` 是稳定 UUID v4；同一业务重试沿用它。`type` 只允许 supplier、contact、product、project、project_item、inquiry、quotation。字段模式取实际本体；宿主不支持 oneOf/条件模式，因此发布字段联合，再在批准前及事务内检查所选类型的精确白名单。未知字段、受保护字段 merged_into/attachment_ids/source_attachment_ids/capture_mode 均拒绝；values 只包含修改字段，合并完整载荷后 `validatePayload`，再由 `Store.save` 校验。

quotation 仅开放 quoted_on、lead_time_days、warranty_months、valid_until、notes；价格、币种、税、报价身份及定标字段不可写。通用 create 不能补造必填价格，因此完整报价创建仍用 `inquiry.record_quote`。

执行事务内复核选定对象身份、revision、digest、工作区绑定和 expected_version；新引用必须在人工选定对象中。新建全局目录记录需已选全局询价对象；新项目返回自身 project ref；项目数据不得越出选定项目。业务操作的参数及逻辑范围哈希、结果回执和领域变更同事务写入；跨 invocation 重试不重复生效，换参数/范围拒绝。Store 原 changelog 及宿主审计回执保留。

删除预览必填所有活跃引用对象的 type/id/version；执行时重算 `referencesTo` 加同类型引用，预览漏项/变动或存在引用即拒绝。恢复须明确选定带 revision 的删除回执；询价专属旧桥接器将显式选定交由 v2 会话解析，普通枚举和页面仍排除删除对象。恢复的出向引用必须活跃。

## 覆盖清单与 Q3

`apps/muyon/lib/app/adapters/inquiry/coverage.dart` 登记查询、原 4 个具名写工具、新 4 个通用写工具及人工上下文导入。product_param、spec_records（spec_*）、merge_duplicates、award、refresh_prices 均为 `deferred(REG-4)`，逐项说明派生 ID/级联/快照/批量计划所需专用工具；不虚报已开放能力。

宿主 Folio 隐藏桌面侧栏、移动导航、Ctrl/⌘ 数字快捷键和命令面板的问数据入口；强制初始 ask 或旧任务恢复不能进入对话。宿主设置隐藏助手权限和联网开关，遗留 AskPage 的联网自动批准也排除 hosted。历史 bypass 存储不再提供宿主绕过入口；standalone 保持原行为；智能材料导入保留。

## 两项 Store 实测

使用测试临时 Store，无真实业务库写入：

1. 原 unit_cost 为 0、定标写入 18 后，`withdrawAward` 清除定标字段，但预算 unit_cost 仍为 18，quotation_id 仍指向该报价；**不会恢复定标前旧值**。据此保持定标/撤回为 deferred，未改领域行为。
2. `Store.delete` **允许删除仍被 quotation 引用的 contact**，报价引用保留，会产生悬空活跃引用；`referencesTo` 可识别该引用。新 delete_record 拒绝此删除，且验证预览与选定范围，不改变原人工 Store 删除行为。

## 验证与例外

有效行为 RED：提交 `89034827719ef25dabe991f01f70297407f20ebf`、[专用 run 38028474611](https://github.com/mightyoung/Muyon/actions/runs/38028474611)，4 通过/14 失败；失败为缺少新工具和宿主仍显示助手等行为断言，无 loader 失败。更早 a053b8a 的测试自身类型错误不计有效 RED。

环境例外：当前执行环境没有 Flutter/Dart SDK；官方及镜像 SDK 下载被代理 403 阻断，因此不能在本地运行 Flutter 后再推送。采用仓库既有 GitHub Actions 的 Flutter 3.47.5、专属行为/变异工作流，明确记录云端 RED/候选校验例外。格式化仅在临时副本输出投影，再显式应用到源码；工作流测试源码 checkout，不偷偷格式化待测树。

本地 Python 门禁回归 9/9、doctor 场景 23/23、验证脚本 py_compile 及 git diff --check 通过。Flutter 最终结果及 exact-head run 链接在 PR #31 的验证记录中提供；未完成的 run 不视为通过。五项变异在隔离仓库副本逐项移除版本检查、放开保护字段、放开报价价格、恢复宿主助手入口、降格写效应绕过批准；须对应行为断言失败且源码恢复后再次 GREEN。

499e1f5 候选的全量验证发现字段模式重复携带本体说明文字，导致原 `assistant_production_model_protocol_test` 的 12,000-token 窗口在历史压缩后仍超限；另有新文件格式化后触发的花括号 lint。仅精简新工具字段模式的重复说明（字段/类型/枚举/长度约束及校验全部保留），并补花括号；没有调整共享模型预算或放宽原测试。专属门禁额外运行该原协议测试，最终结果仍以 PR exact-head 证据为准。

原测试保留：注册目录在原冻结目录外精确增加 4 项并继续比较全部原工具；hosted 旧权限测试收紧为整个控件不存在；standalone 测试不放宽。Linux inquiry 现有 Mac 字体截图跳过按备忘录记录，不能据此宣称 Mac 截图、真机或真实模型验证通过。原始 RED/候选日志只在 `/tmp/reg4c-evidence` 和 Actions artifact，不入仓库。

文件所有权：只涉及询价域、专属适配器/桥接/注册、hosted Folio 入口、专属测试/验证脚本/工作流及本回报；没有修改 F5b 的 shared UI state/surface/module_api 新目录。未修改 main、合 develop、强推、删分支或部署。
