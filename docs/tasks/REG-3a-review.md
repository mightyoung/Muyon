# REG-3a 集成复审

2026-10-09；交付 `48b36375c2ea8ebf3c10281e7f6372a9aa52e5b7`，冻结 develop
`01404ae472451f55af5baa6ce76c95af72b0cbfc`，共同祖先 `b87a22b202cf0c3ce1c98aebb4df32af8d08d847`。
非作者 `/root/review_reg3a` 按 REVIEW.md 对最终提交做独立只读复审，无写入。

三点差异 24 文件、1794 新增/317 删除，符合有界任务书。逐项满足：
科研/原型 v2 本体与有界覆盖声明、旧三个读工具 ID/描述/排序及结果保留、
科研项目和文档磁盘摘要解析、原型无绑定对象页、四个科研写入及 add_feedback
经宿主审批/范围/事务守护/回执、旧交换/索引/已接受导入对账和恢复桥接保留。
REG-3b、本机导出门面、完整科研本体/剩余写入、REG-5 明确未完成，未假称覆盖。

升级持久撤销复核：module_grants.dart:112 保留历史 revoked 墓碑并拒绝陈旧
decision 覆盖；module_host.dart:435 检查全部撤销。显式 reconsider 只清指定撤销、
重算静态策略，不授予 raw tools/knowledge/models。prototype module_tools.dart:115
在 runtime await 后同步复核 page/version/feedback 归属及摘要，直到读取无 await。

保护测试例外仅批准 prototype_tools_test.dart:67 的精确工具目录两项→三项：
保留两旧 read ID、精确总集合、唯一新增 write、无 external 及原行为检查。
其余撤销断言加强失败关闭，无泛化 skip。新增真实数据库、审批及并发屏障测试
检查实际行为，不用 sleep；未发现新秘密输出、越权外传或虚假真机证据。

精确交付 [CI 37961770816](https://github.com/mightyoung/Muyon/actions/runs/37961770816)
已核 head_sha 和 completed/success；日志为 analyze 8/8、test 8/8、host +1267 ~3。
本地 diff --check 通过；本环境无 Flutter/Dart，官方下载 CONNECT 403，未冒称本地
重跑。最新 develop 组合验证由临时审查分支 Linux CI 完成，成功后才发布。
独立复审无确定阻断/应改；scopeSources 的旧注释为可选、不改实现。
最终发布及组合验证证据统一记入本轮集成交接摘要。
