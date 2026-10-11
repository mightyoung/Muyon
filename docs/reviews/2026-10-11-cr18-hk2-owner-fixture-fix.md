# CR18 HK2 当前规划 owner 夹具修正

保留失败组合 `818491ee0a4fc0eb7d5d587c9f70a265c0737b60` 和 run `38168447709`（3814 passed / 207 skipped / 2 failed）。原 HK2 文件在该固定提交本地为 1 passed / 2 failed / 0 skipped，10.644 秒自然 exit 1，无外部超时。失败两例未调用 planUi 安装 request，而是将手工 validated plan 塞入带三档 preference 的 workspace；Parent 主审独立确认此前提不属于合法生产打开入口。

仅修正 HK2 测试夹具，不修改生产代码、owner 门禁、默认模式、skip、CI 命令或 coverage baseline。真实 MuyonHost、SQLite、task、preference 和 taint 检查仍保留。使用真实 PersonalAgent/Harness 调本地受控 source/provider，实际安装 current request 并返回其同引用 validated plan，未构造/伪造 owner，也不以 agent=null 或关闭 preference 绕过门禁。

独立 registry 避免 host-ui-planning 重复注册；复用真实 host 的数据库、scope resolver、grants、grant context、category/policy revision、host scope resolver，以及原 agent 的模型授权、gate、tool reviewer 和 device。无模型请求；没有配置 businessActions。历史断言仍查真实同一 SQLite 的工具记录。新增失败清理也关闭 fixture agent/registry，避免负例遗留后台资源。

原三个 testWidgets 注册、场景 body 与所有断言逐字节保留，SHA256 `54a233135fce5d726e34b64aa0943418a083d8eacd57a9dfa61638ddf4be9003`。新增未绑定旧手工 plan 负例：真实 automatic/request 内容资格仍可用，但没有安装 presentation，卡、事件及工具增量均为零，原回答保留。

HK2+CR18 初始 7/0/0；恢复后 HK2、CR18、SN5 DB/CAS/旧回调及 SN6 回归 31/0/0，20.425 秒自然 exit 0；host strict analyze 零问题。逆变异仅把已安装 request 的返回 cap 换回旧手工 cap：2 pass / 2 fail / 0 skip，6.056 秒自然 exit 1，两个原 ConfirmCard 断言捕获，源码逐字节恢复。准备阶段局部 close 声明顺序的编译错误未计作行为 RED 或合格变异；原始日志留仓库外。

此提交交 Parent 静态 diff 复核，并以包含 a311b252 develop 的新固定 SHA 跑完整组合 CI；旧失败 run 不改、不重跑冒充修复。生产 lib/.github/scripts 的 tree 与 818 完全相同；实际新 CI 终态、完整日志和 source inventory/DA/旧 floor 核验完成前不合入 AIUI。没有真实模型、Android、构建安装、默认开启或部署。
