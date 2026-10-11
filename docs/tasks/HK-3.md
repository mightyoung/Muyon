# HK-3 询价 contact / product 补进宿主变更日志（排在 HK-2 之后）

分支 `task/hk-3-inquiry-change-log-contact-product` · 基线 develop · 执行：Claude Haiku 5.5 · 审查：leader A（数据库迁移，会做变异）

## 问题（GB-3 缺口 G1，严重度高，leader A 已核实）
`apps/muyon/lib/app/inquiry_plugin.dart` 第 2 版迁移（约 62～125 行）只给 `supplier`、`inquiry`、`quotation`、`project`、`project_item` 五张表装了写宿主变更日志（`muyon_change_log`）的触发器。但通用写工具 `inquiry.create_record` 等（`apps/muyon/lib/platform/inquiry_record_tools.dart` 的 `_recordTypes`）还能写 `contact` 和 `product`。结果：助手新建或修改的联系人、物料**不进投影目录**，助手之后按目录查找会以为它们不存在。详见 `review/gb-2-research-write-contracts` 分支 `docs/reviews/2026-10-11-change-log-coverage.md` §3、§4 G1。

## 要做的
1. 在 `InquiryPlugin` 的宿主 schema 里**新增第 3 版迁移**（不要改第 1、2 版）：照第 2 版的触发器模板，给 `contact`、`product` 两张表装 INSERT / UPDATE / DELETE 三个触发器，并用 `INSERT … SELECT` 给已有行补种日志。
   - `native_project_id`：先读这两张表的 `data` 里实际有哪些字段（看 `packages/supplier_core` 的本体或 `validatePayload`）。有 `project_id` 就用它；没有就写 `NULL`（GB-3 说明 NULL 对应全局项目语义），在提交说明里写清你看到的字段。
   - `summary`：沿用第 2 版的 `coalesce(name, title, subject, code, id)`。
   - 同步更新 schema 顶层的 `version` 和 `definitionDigest`（照第 2 版的写法生成新的摘要字符串，如 `'inquiry-host-v3:domain12:change-log-contact-product'`）。
2. 不碰 `product_param`、`spec_*`（GB-3 G4，中等，以后再说）；不改投影服务和工具代码。

## 测试（先写，确认在改之前失败）
新建 `apps/muyon/test/hk3_inquiry_change_log_contact_product_test.dart`，先找现有测迁移和变更日志的测试照抄夹具（搜 `muyon_change_log`、`ModuleChangeLog`、`object_catalog`）：
1. 新建 contact 后，`muyon_change_log` 里有一条 `object_type='contact'`、`op='upsert'` 的记录；
2. 修改 product 后有新的 `upsert` 记录，`revision_ref` 等于新版本；
3. 软删除（`deleted=1`）后记录 `op='delete'`；
4. 从第 2 版升级：先在只装到第 2 版的库里插入 contact 和 product，再升级到第 3 版，两者都被补种；
5. 走一遍宿主投影：新建的 contact 能在 `object_catalog`（或现有的目录查询接口）里查到。

## 自检
- 变异：删掉 contact 的 INSERT 触发器 → 测试 1 失败；删掉补种语句 → 测试 4 失败。恢复后 `git diff` 只剩正式改动。
- `apps/muyon` 的 `flutter analyze`（0 个问题）和全量 `flutter test`。保留代理设置，`NO_PROXY` 加 `localhost,127.0.0.1,::1`；不导出 `MUYON_EVAL_REAL`。
- 只格式化改动过的文件；`pub get` 生成的 `xcconfig`、`Podfile`、`analysis_options.yaml` 改动要还原。

## 回报
提交哈希；contact / product 的 `native_project_id` 用了什么及依据；5 个测试结果；两次变异结果；analyze 与全量测试数字。
