# AUTH-1b B12 leader 精确复审与集成门禁

leader B 已批准接纳 `task/auth-1b-b12-fixes@d4ece4a22889341c1fad33bfd300f6d0d4d3f528` 的 B1/B2 已审基础与边界修复；未批准夹带未审 B3/C，main/release 不在授权范围。复核报告来自父独立 reviewer，原件仅 `/tmp/AUTH-1b-B12-repair-independent-review-d4ece4a.md`；本文件保存摘要，不提交原始日志/探针。

## 父独立复核结论

COMMENT / 可接纳；旧 P1/P2 已关闭，无新阻断。原 paired TLS expiry probe 现在 status=failed、ledger failed/bytes_sent=0、inbox 空；原首次祖先换链 probe 返回 unknown。新增重开 owner/producer、合法 macOS 系统别名、规范路径与用户链接回归通过。亲跑 probes +3、定向 +51、strict `No issues found! (ran in 12.5s)`；未冒称此轮亲跑作者全量或变异。exact CI [37731121849](https://github.com/mightyoung/Muyon/actions/runs/37731121849) 的 headSha 完整等于 d4ece4a，completed/success；远端分支 SHA 也相同。旧 af35297 的失败结论不追溯改写。

WATCH：绝对但非规范路径拼写（尾斜线、重复斜线、. 或 ..）和用户自定义目录链接会降为 unknown/manual。MUYON_DATA_DIR.absolute.path 和 public_files 字符串拼接未必规范化，这是静态兼容性限界；未宣称测试所有配置。后续若改善，应在可信宿主 root 设置处规范化，并保持受管祖先链接拒绝。此证明不是 inode/OS ownership 或原子文件系统快照；bytes_sent=0 仅指未交付正文 chunk，不表示 TLS/HTTP 握手零字节，不承诺撤回已交付 chunk。

## 完整集成范围

最新 fetch 的 remote develop 为 `e473b9c205a215b440b56e465b5e357b21c8eff4`。d4ece4a 包含 7b5e041、2dc89ec、304da36、b3a7de4、af35297、202bd27、d4ece4a 七个 B1/B2/修复/审查提交，相对 develop 共 42 文件。`6c05bdf9efbcefaed6fda21b5d5fcf100634688d` 不是 d4ece4a 的祖先；未带入 B3 optional/manual consumer、AgentContext/PersonalAgent 接线或取消 WIP。B1 已有的 AgentDispatch 变更是来源污染落库，不能称为自动 grant 调度完成。完整范围交叉复核另记。

文档提交不改变已审生产代码；文档 HEAD CI、普通 merge 集成树与 postmerge CI 的精确 SHA/结果由执行回报提供。合入前再次 fetch develop；出现新增代码差异则重新核对，禁止 force push。历史 DB 保留，UI/REG 不重做。B3 已在 `task/auth-1b-b3` 隔离继续，C/真机后置。
