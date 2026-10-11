# SN-1 审查（leader A，2026-10-11）

提交 `d0c6520` · 结论：**通过，可合入**；一处测试缺口另派 OC-4。

- 改动最小：`UiSurfaceController` 新增 `externalContentProbe`，`externalContent` 失败即关闭（无探针、探针抛错都为 `true`）；动态 `ConfirmCard`、`BatchConfirmCard` 传入该值；`DynamicWorkspace` 用 `authorizationFacts.readTask(taskId).requiresConfirmation` 作为探针（`unknown`、`tainted`、查不到都算外部内容）。来源只有宿主事实，计划和界面状态写不进来。
- 复跑：`muyon_ui`、`apps/muyon` analyze 无问题；`sn1_dynamic_confirm_external_test.dart` 9 例通过。
- 变异：

| 变异 | 结果 |
|---|---|
| `externalContent` 恒为 `false` | 检出 |
| 探针抛错时返回 `false` | 检出 |
| 两张卡都不传 `externalContent` | 检出（7 例失败） |
| **没有探针时默认 `false`** | **未检出** |

- 缺口：测试都带了探针，「没有探针」的默认值没有被测住。`import_review_projection.dart:171`、`inquiry_list_review.dart:231` 打开工作区时不传探针，靠的正是这个默认值。已派 OC-4 补测试。
- 行为变化（预期内）：上面两处不传探针的界面，确认卡现在会显示外部内容提示、批量卡不再有「全部允许」。导入审阅处理的本来就是外部文件，符合不变量 3；询价清单审阅若需要恢复，应由宿主传入真实污染事实，而不是改默认值。
- 与 PR42 的关系：PR42 也加了同名探针（`attachExternalContentProbe`），SN-2 合并最新 develop 时保留一份实现、两边测试都要通过。
