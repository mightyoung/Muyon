# 九项旧导航 fixture 的精确迁移提案（未应用）

v2 基于 `3d3813d04529ba454e87e875f81df9d718256262`。本分支仅提交审查文档与可应用补丁，
未应用任何测试差异、未合 develop。对应 leader 明确要求：先把精确例外交用户确认。

## 原因与保护依据

新对象准入要求真实来源 proof、完整 revision/digest pin，拒绝已知但无证明的插件页。
旧测试中的无 proof Fake lease、Research fixture 或缺 pin 引用与该要求不兼容。
本轮用户原指令仅允许 REG-3a 精确旧测试例外；REVIEW.md §测试质量要求核查
“有无修改已有测试来换取通过”。因此此新例外必须确认，不能因 fixture 更真实就自行应用。
这不是 ADR 逐项点名保护九例，不杜撰保护依据。

## 三个旧文件、九个展开执行 case

| 原路径 | 原测试名 | 旧 → 新，只迁 fixture / 初始化 |
| --- | --- | --- |
| apps/muyon/test/dynamic_object_navigation_test.dart | actual_global_inquiry_supplier_opens_without_fabricated_workspace_binding | 原真实 Supplier/id/无 workspace binding 保持，真实 resolver 补 revision/digest 双 pin |
| 同上 | object_page_lease_released_once_and_anchor_restores_from_store | Fake lease/schema → 真实 Inquiry SQLite/schema/页面/lease wrapper；仍查 release 0→1 与持久 anchor |
| 同上 | open_actual_object_and_restore_workspace research | Research fixture → supported Inquiry/fullpin；新名明确 origin research，不冒称 Research 正向验证 |
| 同上 | open_actual_object_and_restore_workspace inquiry | 同一真实 Inquiry 对象经 resolver 补双 pin，往返断言保留 |
| apps/muyon/test/conversation_shell_return_test.dart | shell_object_return_restores_manual_value_node_scroll_and_revision | Research fixture → 真实 Inquiry/fullpin；保手工值、node、scroll、anchor、selection/step、SQLite 重开与修订 |
| apps/muyon/test/conversation_shell_recovery_test.dart | host_generation_replaces_old_listeners_and_leases | Fake lease → 真实 Inquiry 实际 lease 屏障；真实对象在 backup 前初始化，fresh host 使用默认 Inquiry |
| 同上 | restore_during_registered_page_open_stops_late_presentation (resize false) | 真实 Inquiry/fullpin/lease 屏障，保晚页拒绝、pending owner 与一次释放 |
| 同上 | restore_during_registered_page_open_stops_late_presentation (resize true) | 同上，保 resize/session、反向动画及 root stack 断言 |
| 同上 | resizing_inflight_reference_keeps_owner_and_reenables_source | 真实 Inquiry/fullpin/lease 屏障，保 resize 同 owner、source 恢复、第二次页面与释放累计两次 |

仅增加一个测试 support helper。全部原正向、手工稿、scroll、revision、anchor、恢复、
换代屏障、pending owner 和释放计数断言保留，另增加实际 Inquiry 页面可见断言。
marker 在实际页面旁，仅供观察，不以 Text 替代真实业务页，不公开测试绕过构造器。
不修改全局 seedObject、不修改其他 case、不 skip、不减 gate、不改 timeout。
2380 测试与三项 artifact 预览契约/测试完全排除。

## 冻结补丁与独立审阅

[可应用补丁](AIUI-4c-protected-fixture-migration-proposal.patch)，基于上述 3d3813d。
SHA256：`771b641c70d0fe85f4c79fd1213ab3d1f6a84557483589d1b775c8b3ebb86540`。
补丁为 3 旧文件九例的 fixture 迁移及 1 新 helper，相对原 06cb 仅 helper 使用 `super.host` 并移除未使用 import；九例及其断言未变。
原 06cb 审查提交 `0d0c810d9d48f3dab07e20a73e3dfc83c02f557d` 保留。两位非作者逐 hunk
静态复核、亲自 `git apply --check` 通过。没有 SDK 动态执行证据，尚未应用或批准。

已在 3d3813d 源应用自有测试追加（20 项自有回归总计），原追加补丁 `24e9395adcc38493c4ebe5974f6ad2121d33165e196a5cd00581ac66dcccbc27`：
4 项真实 Research 无 proof 拒绝、Inquiry 初始化前已改版的旧 pin 拒绝；不属于旧九例例外。
AAA source/PR CI 真实失败：两项自有 lint 和旧九例；3d 修 lint 后 fresh source 38053961439 / PR 38053964653 尚在运行，未宣称动态通过。
它不是控制 runtimeFor await 内变更的动态复现，不宣称全数据库各表均不变。

批准后才应用旧九例补丁、正常提交新源，非作者精确复审，再运行完整 source/PR/新组合 CI；
全部通过后由唯一 integrator 正常合 develop 并追发布 CI 与远端读回。未批准则保持旧测试。
本分支不作为功能合入包，不发布部署，不修改 main，不删除远端分支。没有原始验证日志。
