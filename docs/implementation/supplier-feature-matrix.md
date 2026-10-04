# 首业务插件：Folio / 供应商功能迁入矩阵

核对日期：2026-10-04。冻结来源：`software-cost-calculator` 的 `origin/main@b35eccbe9ddf458a6538fa107baa9b456972a4f8`；本轮已直接核验该 ref。来源许可证及复制策略见 [supplier-source-manifest.md](supplier-source-manifest.md)。

本文区分源码保留、核心回归、宿主挂载、平台实测；源码复制不表示功能已经在 MuSpace 中通过验收。用户已将供应商插件调整为首业务优先级，科研新增代码保留但不阻塞此路线。

## 核验方法与范围

- 以 `git ls-tree -r --name-only b35eccb` 比对路径，以 `git show b35eccb:<path>` 比对实际内容；未使用来源仓当前 checkout 代替冻结提交。
- 冻结源包括 86 个应用 `lib` Dart 文件、69 个核心 `lib` Dart 文件、70 个核心测试/fixture Dart 文件，其中 67 个为 `_test.dart`；应用侧 51 个 `_test.dart`。
- 所有业务 feature 文件及上述测试均已出现于迁入目录。旧 `main.dart` / 第二个 `MaterialApp` 不迁入，应用入口由 MuSpace 宿主提供。
- 目录映射：`apps/supplier_app/lib/features/<area>/` → `packages/inquiry_module/lib/src/features/<area>/`；`packages/supplier_core/lib/src/` 保持原领域目录；应用测试 → `packages/inquiry_module/test/`。
- 文中的测试文件名是保留/待执行证据索引，不单独代表该用例已经在新宿主通过。当前运行结果记在末节。

## 功能与页面保留矩阵

| 功能 | 迁入页面、面板和编辑入口（均相对 inquiry_module/lib/src/features） | 对应领域能力和已有测试 | 宿主验收重点 |
|---|---|---|---|
| 工作台与命令入口 | `home/home_page.dart`, `command_palette.dart` | `workbench.dart`; `app_test`, `ui_workspace_test`, `workspace_design_audit_test` | 单一 MuSpace 路由、工作区归属、窄屏入口 |
| 项目与成本预算 | `projects/projects_page.dart`, `project_detail.dart`, `project_form.dart`, `budget_table.dart`, `item_dialogs.dart`, `refresh_dialog.dart` | `project.dart`, `pricing.dart`, `project_export.dart`; `pricing_test`, `project_basis_test`, `refresh_test`, `project_export_test`, `business_design_audit_test` | 预算/合同币种税制不可重标，成本数量/附加费用/阶梯价保持精度，原快照不被刷新覆盖 |
| 供应商与物料档案 | `catalog/catalog_page.dart`, `catalog_form.dart`, `catalog_import.dart`, `detail_panel.dart`, `contacts.dart`, `attributes_editor.dart`, `params_editor.dart`, `duplicate_hints.dart` | `tables.dart`, `search.dart`, `search_index.dart`, `material_import.dart`, `duplicates.dart`; `domain_test`, `tables_test`, `duplicates_test`, `material_import_test`, `pinyin_test`, `catalog_test`, `catalog_responsive_test`, `product_source_detail_test` | 联系人/公司资料/参数/附件/来源保留，停用供应商不能进入有效最低价候选 |
| 报价、比价及价格历史 | `quotes/quotes_page.dart`, `quote_form.dart`, `compare_view.dart`, `quote_extras.dart`, `tiers_editor.dart` | `pricing.dart`, `sheet_offers.dart`, `supplier_sheet.dart`; `pricing_test`, `compare_test`, `quote_attention_test`, `sheet_import_test`, `unit_conversion_test`, `quote_form_test` | 精确小数、单位换算、税率/有效期、阶梯量价、项目成交价优先级 |
| 项目询价与成交 | `inquiries/inquiry_page.dart`, `project_inquiries.dart`, `inquiry_create.dart`, `cell_dialog.dart`, `award_dialog.dart` | `inquiry.dart`, `inquiries.dart`; `inquiry_test`, `pricing_test`, `inquiry_page_test` | 询价单/供应商响应/成交动作对应同一项目，不能丢原业务流程 |
| 参数需求、匹配与供应商响应 | `spec/spec_request_page.dart`, `spec_request_list.dart`, `spec_match_page.dart`, `spec_import.dart`, `spec_item_panel.dart`, `spec_widgets.dart`, `param_view.dart`, `supplier_responses.dart` | `spec_extract.dart`, `spec_decode.dart`, `spec_compare.dart`, `spec_deviation.dart`, `spec_migration.dart`; `spec_test`, `spec_parse_test`, `spec_match_test`, `spec_fill_test`, `spec_response_test`, `spec_security_test`, `spec_request_page_test`, `spec_match_page_test`, `param_view_test` | 确定性最低要求不能被模型反转，格式限制/缺项/异常响应不能悄悄跳过 |
| AI 助手及资料导入 | `ai/ask_page.dart`, `ai_tasks_page.dart`, `material_import_page.dart`, `material_review.dart`, `material_source.dart`, `source_input.dart`, `list_review.dart`, `list_to_project.dart`, `offer_form.dart`, `assistant_confirmation.dart` | `assistant.dart`, `assistant_actions.dart`, `assistant_evidence.dart`, `assistant_toolset.dart`, `ai_jobs.dart`, `ai_runtime.dart`; 全部 `assistant_*_test`, `ai_*_test`, `material_review_test`, `ask_page_test`, `assistant_permissions_test`, `assistant_procurement_ui_test`, `ai_workflow_cancel_test` | 保留 readOnly/confirmWrites/用户设置语义；资料/网页/模型不授予写权限；候选、证据、确认和入库分离；取消/重启不重复接纳 |
| AI 接口与凭据 | `settings/ai_settings.dart`, `settings_page.dart`；共享 `app/app_state.dart` | `llm.dart`, `ai_runtime.dart`, `assistant_context.dart`; `ai_runtime_test`, `assistant_context_test`, `assistant_exchange_privacy_test`, `security_boundaries_test` | `flutter_secure_storage` 保存 API key；settings 只存端点/模型等非密钥字段；MuSpace 命名空间隔离旧安装，不以明文 fallback 代替系统安全存储 |
| 数据中心、关系图与质量 | `data_center/data_center_page.dart`, `model_tab.dart`, `ai_tab.dart`, `quality_tab.dart`, `param_migration.dart`, `relation_graph.dart`, `ontology_graph_host.dart`, `ontology_payload.dart` | `ontology.dart`, `data_quality.dart`, `agent_tools.dart`, `mcp_server.dart`; `ontology_test`, `data_quality_test`, `data_quality_scale_test`, `agent_query_test`, `mcp_test`, `relation_graph_test`, `ontology_host_test`, `graph_fixture_test`, `data_center_model_test`, `data_center_workspace_test` | WebView 图谱资源、对象 opener、缩放/焦点、平台 bridge 的消息边界；关系图不作为第二份事实数据库 |
| 数据交换、冲突、目录同步、局域网 | `exchange/exchange_page.dart`, `conflicts_page.dart`, `folder_sync_panel.dart`, `import_flow.dart`, `lan_panel.dart`, `lan_push_page.dart`, `passphrase.dart` | `exchange.dart`, `folder_sync.dart`, `lan.dart`, `share.dart`; `exchange_security_test`, `field_merge_test`, `merge_test`, `folder_sync_test`, `lan_security_test`, `share_test`, `conflicts_test`, `encrypted_import_flow_test`, `exchange_design_audit_test` | 预览后确认、加密口令、冲突保留、删除传播；异步准备不在 SQLite 短事务内；共享范围及私密助手日志过滤 |
| 备份、恢复与回收站 | `settings/settings_page.dart`, `exchange/import_flow.dart`, `trash/trash_page.dart` | `exchange.dart`, `store.dart`; `backup_test`, `migration_test`, `schema3_test`, `schema4_test`, `trash_test`, `restore_flow_test`, `import_delete_cycle_test` | 恢复保持原确认边界、宿主暂停/等待写入、源备份不改写；不能复用旧应用资料根 |
| Excel/PDF/文本导出与原附件 | 项目/报价/目录相关导入导出面板及 `platform/files.dart`, `platform/cjk_font.dart` | `xlsx.dart`, `project_export.dart`, `attachments.dart`; `excel_test`, `pdf_test`, `xlsx_security_test`, `workbook_text_security_test`, `sheet_text_security_test`, `parameter_attachment_test`, `project_export_test` | 字体加载、导出系统选择器、Android 保存再打开与分享；桌面成功不替代手机验证 |
| Hub 发布和查询 | `hub/hub_page.dart`, `hub_publish.dart`, `hub_settings.dart` | `hub.dart`, `tool/hub_export.dart`; `hub_client_test`, `hub_export_test`, `hub_test` | 原数据发布范围/明确动作保留，连接状态不等于生产发布授权 |
| 任意记录跳转与通用编辑体验 | `records/open_record.dart`；`widgets/data_grid.dart`, `draft_frame.dart`, `ledger.dart`, `deletion.dart`, `price_trend.dart`, `material_icon.dart` | `storage_codec_test`, `store_test`; `ui_conformance_test`, `ui_review_layout_test`, `ui_task_surfaces_test`, `material_editor_layout_test`, `theme_integration_test`, `motion_test` | 长表格、草稿、320/390/430 宽度、200% 字体、键盘/语义/减少动画；不能只验证首屏 |

## archive 3 → 4 适配核查

冻结来源 `bounded_zip.dart` 与迁入副本逐行比对，适配限于：`ZipDirectory.read(InputStream(...))` 改为 `ZipDirectory()..read(InputMemoryStream(...))`，删除 archive 4 已非空字段的 `!`，`rawContent.toUint8List()` 改为 `getRawContent()`，压缩方式整数判断读取 central header。

以下原护栏仍在同一执行顺序内：

1. `_checkDirectory` 在 archive 创建每条目对象前限制中央目录条目数，校验 EOCD/ZIP64、目录长度及歧义注释。
2. 两遍处理：第一遍校验累计声明大小、加密标记、stored/deflate 压缩类型、Unix 文件类型、空名/重复名；第二遍才解压。
3. `_BoundedOutput.add` 按实际输出限制字节，使用 1024 字节压缩输入分片调用 native inflate，不信任声明大小。
4. 解压后逐项核对实际长度及 CRC；未使用的 archive member 也核对。
5. 上层 XLSX/交换格式继续承担路径、工作表、XML、引用和领域验证。保留底层 ZIP 检查不表示可以移除上层检查。

关键回归名：`rejects excessive declared expansion before reading entry content`、`rejects forged small expanded size rather than trusting metadata`、`retains CRC verification, including unused archive members`、`rejects repeated worksheet targets before reparsing empty XML`。以上所在 `xlsx_security_test.dart` 已随下述核心全量测试通过。fixture 的 archive 4 适配为 `file.compression = CompressionType.none`，没有删去 stored ZIP 断言。

## 宿主持有数据库的复核点

- 新增 `Store.attach` 只接受已经迁移的连接，检查 schema；`_ownsDatabase=false` 使模块 `close` 不关闭宿主连接。旧 `Store.open` 保留给独立 core 测试/旧使用方，不能被 MuSpace 挂载入口调用。
- `backgroundExecutor` 注入后，`Store.inBackground` 复用同一 Store；不能继续沿文件路径开第二连接。该 callback 可返回 Future，故不能直接当作 `ManagedDatabase.write` 的同步 SQL 回调；生命周期等待应在事务外完成。
- 原 `Store.transaction` 是同步、可加入外层事务的短 SQL 事务。备份/恢复、后台导入及应用关闭仍需整体集成验证；源码出现 attach 不等于所有路径已切换。
- 已核验 `AppState.attach` 必须注入 `AiJobStore` 和 `InquirySecretStore`；`AppState.open` 已移除，只有测试构造器保留独立 job 文件 fallback。`shutdown` 停止 LAN、暂停 active AI、等待同步/后台写/AI tasks，再由 runtime dispose。`AiJobStore.attach` 不关闭宿主连接。settings 文件、OS secure storage 命名空间和宿主关闭顺序仍由集成回归确认。

## 验证状态

2026-10-04 在最终宿主导出元数据修复后，独立重跑 supplier_core 全套单元测试，结果 **465 passed / 3 skipped / 0 failed**，约 65 秒。该结果替代修复前一轮 464 passed 的基线，包含新增 `host exports round trip through strict standalone import and restore` 回归。命令在 `packages/supplier_core` 执行：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  -u http_proxy -u https_proxy -u all_proxy \
 /Users/muyi/development/flutter/bin/cache/dart-sdk/bin/dart test --reporter expanded
```

本轮受测核心快照：`packages/supplier_core/{lib,test}` 下 140 个 Dart 文件，按相对路径排序、依次拼接 `path + NUL + bytes + NUL` 的 SHA-256 为 `7ad607ff1ce5c6b1ca117ad84e8b3aef70468dfb1b1d7d5c9b702b4527325dcd`。快照摘要用于区分并行修改中的受测源码，不代替最终 Git 提交身份。

运行环境为本机 Dart 3.13 SDK；允许本地测试绑定 socket。第一次受限运行的 LAN `SocketException: Operation not permitted` 属环境限制；同时发现的 archive 4 fixture 编译问题已由迁入代理修复。上面的成功结果来自修复后的完整重跑，不把受限运行视作通过。

三项跳过的条件来自原测试：

- `ai_jobs_test.dart`：缺少 `DEEPSEEK_API_KEY`，未执行依赖真实模型的用例。
- `hub_client_test.dart`：`supplier-hub` 二进制未构建，未执行该真实服务用例。
- `pdf_test.dart`：本机系统 CJK 字体检测未命中，跳过相关字体用例；迁入字体资源仍需要应用端导出验证。

本次还包含新增 `host_attachment_test.dart`，验证 Store/AiJobStore attach 不关闭宿主 DB。应用原 51 个测试及新增宿主测试、真实图谱 WebView、平台安全存储、文件选择器、网络服务和双端数据流程属于另外的验收层；本表不声明设备或完整迁移通过。

后续宿主只读复核及修复验证：

- 发现并实际复现：宿主版 `exportTo` 把 `host_schema_state` / `schema_migrations` 复制进 `.siq`，原领域格式白名单拒绝该文件，导致自己的备份/交换无法导回。迁入 owner 已修复为仅在导出副本移除这两张宿主表、重置副本 `user_version`，保留严格导入白名单。
- 独立实际宿主回归通过：导出文件不包含两张宿主表；同一宿主 Store 的 preview 和 replaceFrom 成功；live 元数据仍在。对照测试：旧应用格式恢复后宿主关闭/重开成功，没有复现“恢复删除宿主 schema”问题。
- `AppState` 已增加关闭 gate，新的普通/后台写和同步在关闭阶段拒绝；独立执行更新后的 `inquiry_module/test/host_attachment_test.dart`，验证在首个后台任务排空前关闭不会完成、晚到写不能执行。
- 上述独立复核共 3 个测试通过，其中两项实际宿主复现/验证保存在临时脚本 `/private/tmp/muspace_host_review_test.dart`；正式回归由实现 owner 加入仓内测试。临时脚本不属于产品。

主执行代理已补上 `AppLifecycleListener.onDetach` 关闭接线、research 工作区切换旧 session 释放和重复 close 共用同一 Future；本轮只重跑 supplier_core，不重复审查或扩大这些宿主修复的证据声明。真实平台退出/恢复操作仍不能由核心单元测试代替。
