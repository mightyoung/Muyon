# PR28 / PR18 固定源集成复审

基线 `b6b56d0929f622b9fae123c17046ba6715672320`；PR28 源
`c9d11a8975b05c2cbf5558de0c9fd2fae1b10cb7`；PR18 源
`44bf146ea06874ee9ebac57feff6c4870b55af86`。按用户授权，仅合 develop。

非作者 review_reg3a、review_grok7 独立核最新修复、旧保护和测试质量，未发现当前确定阻断。
第二轮五项关闭：Prose 每段模型来源标记覆盖显示/语义/复制；单列 CompareTable 消费稳定
排序且 itemId 不变；集合业务输入从 typed selection 层规范化比较并冻结 pending；schema2
持久化人工/view 选择层；恢复按当前 spec 校验，拒绝值只留可读稿、不活化。
旧回调、Tabs 回落、view 业务输入、row-open nodeId 和纠正无效人工值的保护仍保留。
新增测试包含真实点击、业务调用次数、SQLite 关闭重开、原字节保留与零业务调用；
既有期待、验证脚本和 workflow 未弱化，没有缓存改动或新增 skip。

作者[真实 Claude 报告](AIUI-5-F5c-revision2-claude-review.md)首轮审 afce5b96、最终兼容续审
9c33d8ed；9c33d8ed 到 c9d1 仅两份文档，生产与测试字节一致。报告为源码审查，未重跑测试。
本云端没有 Claude/Flutter/Dart；我方静态交叉审查不冒称独立验证作者原始 Claude/RED 日志。
[固定源 bot](https://github.com/mightyoung/Muyon/pull/28#pullrequestreview-5478436679)
已终结；三条旧 P1 按修复与测试依据关闭并读回。PR18
[固定源 bot](https://github.com/mightyoung/Muyon/pull/18#issuecomment-6095422778)终结且无主要问题。

应改项明确保留，不作为已修复或完整恢复验收：

- [P2 r4237148073](https://github.com/mightyoung/Muyon/pull/28#discussion_r4237148073)：
  持久隔离稿重开后只读，缺显式恢复/丢弃入口。原字节保留、拒绝稿不活化、直接业务调用
  被阻止，符合现行不兼容恢复规则，故本轮非硬阻断。直接解除只读会改变该规则；后续须
  明确操作与身份/spec/CAS 校验，该线程保持 open。
- DynamicWorkspace 页面先 store.load，坏 codec 在页面被捕获，尚未接 controller 的
  可读稿保留分支。当前安全报错而不改字节，应补真实页面用例与接线；不能称端到端可读。

[源 push38039746441](https://github.com/mightyoung/Muyon/actions/runs/38039746441)、
[PR38039749864](https://github.com/mightyoung/Muyon/actions/runs/38039749864) 均成功；PR 实际
checkout f4cee9004397352f01f13f21eff8d711286894df 父提交为上述 develop 与 PR28 源。
主动建立最新组合 `08c420ca134c6e6574ccd86208e32631ea2d12e8`，
[CI38040673330](https://github.com/mightyoung/Muyon/actions/runs/38040673330) 成功：分析/测试
8/8，host1528/3skip，API190，UI373/152skip，doctor23，Laya29。F3b 11 项真实重算验收
纳入宿主全量，同 controller/session/field、30/40、extracted2、顺序采用及数据库零写入保留。

正常 no-ff PR28 集成 `ce139cab4cfde335fd685efd5988f1ad86593c66`，随后 PR18
`8c0584c90d9d219e46af5cc96f6e0c82597fb7ea`；整树等于已测组合，仅另附本摘要与索引更新。
发布 HEAD/远端读回/发布 CI 终态见执行回报，原始日志不入库。
多列排序、完整恢复体验、F4c await 后 scope/lease、设备/goldens/真实模型及14未来场景仍未验收。
