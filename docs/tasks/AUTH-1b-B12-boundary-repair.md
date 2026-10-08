# AUTH-1b B12 边界修复

基线 `af352970d8477f29e6b0ee04ebcbd4fde7539c34`，独立分支 `task/auth-1b-b12-fixes`。父独立审查的结论为 REQUEST CHANGES：旧 strict、166 专项和 CI 成功没有覆盖下述两个窗口，不能作为该基线无条件集成的依据。本分支只修 B1/B2，不包含 `6c05bdf` 的 B3 部分提交或取消修复 WIP；A/REG、UI、历史 DB 和 main/release 不变。

## 修复与行为证据

- P1：TLS 正数进度回调在 chunk 交给 HttpClient 前可同步使审批到期或撤销工具权限。回调返回后重新执行宿主 guard，随后才累计 sent/ledger count。被拒绝的 chunk 不计已发送；不承诺撤回已交付字节。新增真实配对 TLS 回归，不提供 caller guard；两种回调均断言失败账本、bytes_sent=0、接收 inbox 空。
- P2：首次懒 pin 和新 owner/producer 不再信任任意 resolve 后的外部 namespace。证明前检查绝对、规范路径的全部词法祖先，拒绝受管路径及用户路径中的符号链接；仅明确接受 macOS 的 `/tmp -> /private/tmp` 与 `/var -> /private/var`，并核对实际目标。保留原 canonical pin 及两轮复核。新增首次 proof 前替换祖先，以及已 swap 后重开 DB/producer 的回归，均须 unknown。

先在旧代码运行新增四条行为回归，四条全部失败（实际 TLS 成功发送或返回非 null stamp）；编译失败、未匹配测试不计 RED。最小修复后 scope/TLS/传输状态/聊天后台 31 项通过。所有夹具使用独立临时 DB 与真实本地配对 TLS，不是实机或真实模型证据。

原始日志、故障探针与变异 driver 只在 `/tmp`。最终严格分析、全量、恢复后变异、独立复核及 exact-head CI 结果在后续证据段记录。未证明来源继续 unknown/manual；未启用生产 Agent 自动调用；B3/C 与实机后置继续由父任务安排。提交推送后先复审，本分支不自行合 develop。

## 作者验证

- 首轮 strict：`No issues found! (ran in 7.1s)`；完整宿主 `+1013 ~3: All tests passed!`。
- 两项有效行为变异均退出 1，且对应新增两条断言失败：移除正数回调后的 guard、移除 namespace 祖先链校验。编译错误与未匹配测试未计入；两份实现逐字节恢复。
- 恢复后 strict：`No issues found! (ran in 6.3s)`。恢复后完整宿主 `+1013 ~3: All tests passed!`（1m45s）。
- 定向 31 项通过，包括实际配对 TLS、sent==0 边界、实际 peer identity、正常发送、scope 与 transfer 状态/聊天后台。撤销回归操作真实 ToolRegistry availability，不冒称已发送字节可撤回。

最终独立复审与 exact-head CI 尚待提交后执行；当前作者绿灯不代替父复审。
