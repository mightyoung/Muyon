# WC-D-F：回执查核完整性补修（CR-16 I-1、I-2、N-1）

执行：Haiku。派发：leader A，2026-10-11。集成：Leader B。基线：PR #50 head `01fbed45`（你的 WC-D `ef75f933` + Leader B 完整性补修）；分支 `task/wc-d-fixes`。依据：`task/cr-15-17-chatgpt` 分支 `docs/reviews/2026-10-11-wcd-pr50-review.md`。只改 `apps/muyon/lib/platform/inquiry_receipt_lookup.dart` 与查核测试；不动写工具、旧 `reg4c:` 身份规则与写入口顺序。Codex 正在同一基线上做 WC-C（改 `inquiry_record_tools.dart` 出口），注意别碰那个文件。

## I-1 create 结果 ID 格式
历史 create 回执的 `result.data.id` 与 `objectRefs[0].objectId` 必须是合法小写 UUID（复用 `packages/supplier_core/lib/src/values.dart:33-40` 的规则）。
测试：真实 create 回执，把两处同时改成 `"not-a-uuid"`（参数不变、version 1）→ `unreadable`、`succeeded == false`、`receipt == null`。
## I-2 历史请求结构
在身份比较之前按旧回执协议检查：create/update 的 `parameters.values` 存在且为 Map；delete 的 `referencing_records` 存在且为 List；`arguments.scope` 解析后为 `{workspace, objects:[{moduleId, objectType, objectId, nativeProjectId}...]}`。不合格 → `unreadable`。通过后仍用**原始存储字符串**算摘要。不得借重新执行写工具或读当前对象来验证。
测试矩阵：上述每项各删除 / 置 null / 换错类型一例，加 scope 为 `"{}"` 一例，全部 `unreadable`；原有正常 matched / identityConflict / notFound 用例保持通过。
## N-1 只读验收走 runtime
经已激活 runtime 的 `BusinessReceiptLookup`（`InquiryModuleRuntime.lookupBusinessReceipt`）验收 matched / identityConflict / notFound / unreadable 四路径：前后比较领域库与宿主库 `total_changes()`，并记录 `AppState` 监听回调次数为 0；保留现有行数与版本断言。

## 变异（必须做）
去掉 UUID 校验；去掉 `values` 存在检查；在 matched 分支加一次 `state.changed()`。三个都必须被测试抓到。

## 回报（固定 6 行）
1. RED 提交哈希与 I-1/I-2/N-1 各自失败第一行　2. 修复提交哈希（远端与本地一致）　3. 改动文件与行数　4. 变异结果　5. analyze 与 `muyon_module_api`、`inquiry_module`、`apps/muyon` 全量（pass/skip/fail）　6. 未做或有疑问
