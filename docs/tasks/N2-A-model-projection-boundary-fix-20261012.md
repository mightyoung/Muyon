# N2-A 合入后模型投影边界补修

基线 develop `1a0131866ab33d87462ca49b3e4d75264b55e36a`。此前 bounded native preview 已合入；晚到审查不能由旧 CI 或「当前无消费者」关闭。

I1 原独立测试确实执行了 deleteSection 并比较 entries，但缺少 documents/runs 独立表差分与明确删前 digest 对照。新增 `n2_projection_boundary_regression_test.dart` 使用真实临时 SQLite 文件，关闭后复制为第二独立数据库：两副本全表相等、两个删前 digest 与 preview 相等、实际删除四条完整 outline 关联（包括错误 project metadata）、entries/documents/notes/tasks/runs 及其余声明保留表逐行 JSON 字节不变，原 source 全表不变。该用例已实际通过，不把 complete/evidencePreserved 常量本身当作证据。

另摘入 PR60 固定 `864fdb74f6d2bf4c4229f8d0a12d9b113dc52692`，仅其独立测试与 helper 两文件，未改任何断言/帮手。独立重跑 20 通过、0 失败、0 跳过；其中真实 VACUUM INTO 双副本、Store/handler 删除与 digest 拒绝/新鲜 positive control 是真实 SQLite fixture 中的 handler 证据，直接夹具调用绕过宿主审批，不代表完整生产删除确认链。

I2 真实缺陷：capture 的 native canReadEvidence 默认本机可读，经 link.toModel 直接把关联/证据身份送入模型 DTO；DTO 还自动带出隐藏章节/关联内容相关的 deleteDigest。新负例在固定 RED `47b97c6c0fca20a969015d66d027322057115465` 实际 1 通过、3 断言失败（默认标识、本机回调被误借为模型授权、隐藏内容相关 digest）。首次夹具文档列名错误单独留日志，不算 RED。

最小补修：模型专用 link.toModel 只返回统一 restricted 状态，去除关联/证据标识、类型、可推断其排序位置的行差异；SectionDeletePreview.toModel 不带 deleteDigest。native preview.links、canReadEvidence、local deleteDigest、实际 deleteSection、宿主授权与 CAS 均保持原行为。本机读取资格不借作模型披露授权。旧作者模型测试两条正披露断言升级为明确不得披露；其余测试保留。自己的四负例与 PR60 20 及此前 22 targets 已实际 46 通过、0 失败、0 跳过。

实际接线核对：source 只改 core/app preview、writing_page 与测试。`module_tools.dart` 的 read_object(section) 与 outline_sections 仍只附原 deleteDigest，没有接新 preview；生产 lib 中 SectionDeletePreview 当前消费者只有本机 Dialog，模型 DTO 暂无生产消费者。因此完整原任务关于 read_object/outline_sections 的 preview 交付是部分满足，后续模型接线仍须独立授权/披露审查。本补修关闭的是 DTO 默认暴露缺陷，不声称真实模型外传已验证。

此前 hostzero 验证另真实打开本地 MuyonHost，两个独立 observer 连接比较真实 host/research 全表，明确存在 tool_approvals/tool_invocation_receipts，打开/刷新/关闭 native preview 无表变化、total_changes 增量或业务回调。这是实际 SQLite 测试宿主夹具证据，不是生产用户 journal。

原始日志在 `/workspace/reports/n2-boundary-fix-20261012`，不入仓库。独立复审、逆变异恢复、完整本地/CI 门禁以固定最终提交另核终态；不以以上 target 通过替代。未修改原作者分支或预留外部测试文件，未合 develop/main、强推、删除分支、运行模型或 Android。
