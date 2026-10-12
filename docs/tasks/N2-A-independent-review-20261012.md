# N2-A 只读章节删除预览独立复验

固定作者源 `da5b482619fde2dbaca0c84603135b1b81e94f13`；独立组合基线 `9d8a4118de74cda369ddd004c519d01a1e0752ba`。源分支 remote 完整 SHA 经核实未替换。作者 RED `6f05ae5` 与最终实现均摘入，保留最终全部测试；未改作者分支。

实际源范围五文件：core/app `section_delete_preview.dart`、`writing_page.dart`、两份 preview 测试。没有修改 module_tools、删除授权、写 CAS、schema 或公共 `research_module.dart` 导出。审查分支另增独立行为测试 `n2_preview_independent_review_test.dart` 与本报告。作者五文件组合 blob 均与固定源一致。

## 行为与边界

- `OutlineStore.deleteSection` 实际删除所有 `outline WHERE section_id=?`，再删除章节；外键为普通 REFERENCE，没有额外 ON DELETE CASCADE。预览和既有 `sectionDeleteDigest` 完整使用同一关联谓词，并按关联 id 排序。错误项目关联仍计入删除数量，详情为 restricted；不虚构历史证据类型，裸 ID 显示 unknown。
- scope、关联数量、包括隐藏字段的字节预算在物化/完整 digest 前拒绝；全量预览失败不退化成部分成功。own BEGIN DEFERRED/SELECT/ROLLBACK 保持一致读快照，不提交或回滚调用者已有事务。
- 独立真实两个 SQLite 连接比较全部表（包括科研日志、宿主 change log、回执）、双方 total_changes 以及拒绝写入的 ManagedDatabase：capture、预算/范围拒绝、freshness、权限变化均没有写入，也无先写后回滚。另一独立测试实际执行既有 deleteSection，确认完整两关联被删除、证据实体和其他章节关联保留，旧预览保持冻结且变 stale。这是本地测试数据库证据，不是真实业务删除验收。
- 写作页入口只创建新只读 modal，预览无确认/删除动作。既有删除按钮和授权链保持原状。该片没有把 preview 接入助手 read_object/outline_sections，也不闭合删除确认与提交 CAS；不能称 N2 全链完成。

## 独立实际运行

Flutter 3.47.5 / Dart 3.13.4，Linux，未运行真实模型、Android 或设备操作。

| 验证 | 实际结果 |
| --- | --- |
| 作者两份 preview 文件 | 20 通过，0 失败，0 跳过 |
| 新增独立两连接/真实级联对照 | 2 通过，0 失败，0 跳过 |
| 当前组合 research_module 全量 | 328 通过，0 失败，0 跳过（当前基线 306 + 作者 20 + 独立 2） |
| host outline/order/changes/rollback 四文件 | 30 通过，0 失败，0 跳过 |
| host reg3cf_evidence_type | 5 通过，0 失败，0 跳过 |
| research_module / apps/muyon strict analyze | 两包均 No issues found；无 info 忽略 |

第二非作者只读复审又运行实际级联与同 key 重用 characterization 2 例、320x700/200% 字体/万字标题滚动与关闭按钮可达 1 例，均通过。作者 320/390 宽度、200% 字体列表/过期刷新用例由本审查独立重跑。第二复审 C0/I0/M1，报告与原始日志保留仓库外。

## 逆变异

在独立组合工作区临时逐一施加七处逆变异，均真实自然 exit 1，均有 completed done(success:false)，不以编译失败、加载失败或超时算检出；每次恢复原字节。以下为失败测试数，组件 error 是 widget 行为诊断，非 test-loader 失败。

| 逆变异 | 检出 |
| --- | --- |
| 去掉 capture 入口 scope 检查 | 1 widget error：越界应为固定拒绝而非意外 StateError；digest 仍有第二道 scope 守卫，不能称全部授权被绕过 |
| 过滤跨项目级联关联 | 3 断言失败，独立真实删除数量对照也失败 |
| 放宽 maxLinks 至 5000 | 3 断言失败、1 widget error |
| 放宽 maxBytes 至硬上限 | 2 断言失败 |
| 裸 ID 硬编码 entry 类型 | 2 断言失败、2 widget error |
| digest 改变仍视 current | 1 断言失败、1 widget error |
| 不启动 own 读事务 | 1 断言失败：另一真实连接写入后快照混杂 |

恢复后 22 个 target 全部通过、0 失败、0 跳过。core 文件 SHA256 `fc445a4d071427dd83f85c66695504118c8afb3d347b9d2bcb596068c364a818`，等于固定源；无产品代码补改，无删改作者测试。原始 JSONL、analyze、变异日志均在 `/workspace/reports/n2-preview-independent-20261012`，未入仓库。

## 限制与合入条件

M1：通用 Dialog 没有 didUpdateWidget。若外部未来用同 key 改 store/projectId/sectionId，旧快照会保留并标 stale；当前 WritingPage 每次创建新 modal route，workspace 对项目使用 ValueKey，没有这条同实例换选择生产路径。不能声称支持通用复用换对象。现有固定新 route 不因此阻断。

本片没有新增 C/I 阻断。可合入条件为固定独立组合完整 CI 成功，完整 SHA 与 checkout/八套 analyze/test 门禁相符；独立本地通过不代替 CI。CI 运行与最终终态另以固定 SHA 的 Actions 和仓库外 proof 核验。本审查不 merge develop/main，不 forcepush/delete/deploy，不改变其他活动 writer。
