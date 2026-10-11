# WC-D 询价业务回执查核 + PR #50 独立复审（CR-16，ChatGPT）

固定 WC-D `ef75f933`、PR #50 `01fbed45`（base 为 WC-D，只改查核实现与测试两文件）；云端只读，未运行测试；远端 CI 38138528174 success。原稿由用户转交，leader A 整理入库。

**结论：需修改。** 2 项 Important、1 项 Minor；无 Critical。查核生产路径只读，旧 `reg4c:` 身份规则与单条写入口防重顺序未变；但历史回执完整性缺口未完全关闭（两项 Important 都是对已存回执构造损坏后的静态反例，WC-D 基线已存在）。

| 编号 | 级别 | 问题 | 位置 | 验收 |
|---|---|---|---|---|
| I-1 | Important | create 回执把 `result.data.id` 与 `objectRefs[0].objectId` 同时改成 `"not-a-uuid"`（参数不变、version 1、deleted false）仍返回 `matched`、`succeeded == true`：只拒空白 ID，create 不比较请求目标 ID，只要求两处一致。正常新建 ID 来自 `newUuid()`（小写 UUID v4） | `inquiry_receipt_lookup.dart:95-141`（110、112、127-131） | 对历史结果 ID 做固定格式只读校验（复用 `values.dart:33-40` UUID 规则）；该用例须 `unreadable`、`succeeded == false`、`receipt == null` |
| I-2 | Important | 历史请求必填结构未校验：删掉 update 的 `arguments.parameters.values` 后返回 `identityConflict`，应为 `unreadable`。同类：create/update 的 `values`、delete 的 `referencing_records` 缺失 / null / 错类型；`arguments.scope` 只查非空字符串（`"{}"` 也过），未查 `workspace` + `objects` 四字段形状 | `inquiry_receipt_lookup.dart:74-123`（86-100）；schema `inquiry_record_tools.dart:128-134`；范围形状 `inquiry_write_receipts.dart:36-49` | 身份比较前按旧回执协议检查各操作必填字段、类型与范围结构；通过后仍用原始存储字符串算摘要；不得借重新执行写工具或读当前对象来验证；补测试矩阵 |
| N-1 | Minor | 只读验收直接调 `lookupInquiryReceipt`，绕过 `InquiryModuleRuntime.lookupBusinessReceipt`；快照比行数，抓不到等行数更新与 `notifyListeners`；`total_changes()` 只在损坏路径断言 | `wc_d_inquiry_receipt_lookup_test.dart:422-468` | 经已激活 runtime 的 `BusinessReceiptLookup` 验收；匹配 / 冲突 / 未发现 / 不可读四路径比较领域库与宿主库写入计数（`total_changes()`）并记录 `AppState` 监听次数 |

## 核对通过
- 生产路径只执行 `PRAGMA database_list` 与参数化 `SELECT value FROM meta WHERE key=?`，无 `state.write`、写工具、审批、调用回执、通知。
- 五态：正常身份比较成立；`notFound` 只在读到 meta 且无键时返回；本查核器不返回 `unknown`（在途调用判定属宿主恢复调度片 E），不作本片阻断，但不能宣称端到端五态恢复已验收。
- 旧 `reg4c:` 规则不变：键、请求身份（operation + 完整原始 parameters + scope，含原 `expected_version`）、递归排序键、列表保序、范围身份不含 revision/digest。
- 历史版本恢复保留；普通写入口仍「先查当前 selection → 查旧回执 → 未命中才查目标状态与 expected_version」。
- 测试未删减或放宽（先补特征测试 `be872f32`，再抽取 `b8023f02`）。
