# AIUI-6 / REG-3b 独立集成审查

本批基于 develop `a68ba43d0c8c1b64c632e4b4b30cca9a2b208956`，依次正常 merge AIUI-6 与 REG-3b；唯一 develop 合入执行者负责推进。原 AIUI-36–39 逐条证据继续保留，本文件不替代它。

| 候选 | 冻结完整 SHA | 独立动态证据 |
|---|---|---|
| AIUI-6，PR #40 | `650f51a381d6891d16199bf435fe2ef1ed97cd6c` | [source CI](https://github.com/mightyoung/Muyon/actions/runs/38055358701)、[PR CI](https://github.com/mightyoung/Muyon/actions/runs/38055362309) 均 SUCCESS；host 1571 pass / 3 skip，8 analyze / 8 suites、doctor 23、Laya 29、coverage OK |
| REG-3b，PR #41 | `2fbdd6952727756574200cc5d9bd181b5a67097a` | [source CI](https://github.com/mightyoung/Muyon/actions/runs/38055913908)、[PR CI](https://github.com/mightyoung/Muyon/actions/runs/38055916500) 均 SUCCESS；host 1555 pass / 3 skip，8 analyze / 8 suites、doctor 23、Laya 29、coverage OK |

两项最终源码均有强模型非作者静态复审，AIUI-6 的 15 个自有测试与 REG-3b 的 13 个自有测试原样保留。REG-3b 前一版 `c067a6e3f76ccde11864337ffdab919393c09416` 的 CI 曾因新增测试错误重复绑定 workspace 失败；最终 2fb 仅修正自有夹具为合法创建并首次绑定另一 workspace，验证真实 authority 变化，不修改生产校验、旧测试或门禁。

代码组合 `f8c50517d370946b99645b9861bc01cdf999e918` 经独立非作者逐项复核：两项增量分别 6 / 10 文件，路径无交集，全部 blob 与各原 source 相同，无额外产品改动。既有 AIUI-4c/9、ModuleHost、UI core、保护测试、CI、coverage baseline 均未改变。AIUI-6 的独立 Inquiry resolver 不调用 REG-3b knowledge hook；REG-3b 注册 research search source 及 runtime provider，并迁移 bootstrap 的 research.document 校验分支，其他模块 hook 保留。

独立 leaf coverage 审计亲读上述实际 source/PR 日志及摘要：AIUI-6 406、REG-3b 403 个 loaded source hash，8 库库存、全部 DA/unhit、43 个严格 gate 文件均复算通过。source 与各 PR synthetic 的代码及归一化覆盖数据一致。baseline SHA256 保持 `a43a0290cd45e638f0b354095bf4978de43b5aea8a9ac4ae99f3280e0174c17b`，19 个未加载文件仍为未知分母；严格自动 gate 仅 API/models/transfer，不能写成全库自动逐文件 gate。

REG-3b 的旧 `index_invalidation.dart` 源码和 DA 集未变，但 8 个旧命中行（8、13、14、15、16、18、19、20）不再命中；bootstrap 的旧 301 → 新 308 `research: () => host.research` 也失去命中。独立强审逐行映射确认均为旧 research.document any(id) hook 被注册 source 校验替代后的路径迁移，未见其他未解释的旧命中丢失，不能声称所有旧命中均保留。其他模块 hook 静态保留，当前 suite 不代表其覆盖增加。修改源码的覆盖比较需映射 diff 行号，不能把行号移动记为真实覆盖丢失。

组合 [CI 38057267224](https://github.com/mightyoung/Muyon/actions/runs/38057267224) 对精确 f8c 已于 2026-10-10 14:07:42 UTC 终态 SUCCESS；亲读实际日志确认 8/8 analyze、8/8 suites：API198、UI373/152skip、prototype39/1skip、research220、supplier498/4skip、host1613/3skip、preview15、inquiry289/47skip，doctor23、Laya29、coverage OK。

组合独立全8库覆盖审计亲读实际409 loaded source blob hash、全部DA/unhit及库存、43gate并复算通过，19unknown原集合保留。API2093/2203、research4682/5500、host16886/19539；其他5库同b41。5个修改源码及4个新增源码的完整records与已审叶源相同；400个源码未变records中，396完全同，其余为已解释的index旧8命中减少、knowledge新增8命中、optional_capabilities新增2命中、ontology adapter新增1命中。5个修改源码逐行映射仅bootstrap旧301→新308失去命中，同旧hook迁移；未发现额外loss/swap，不重置baseline或抬降floor。完整审计仅存/tmp，不提交原始日志。

前一 develop a68 的独立 [发布 CI 38056891075](https://github.com/mightyoung/Muyon/actions/runs/38056891075) 已 SUCCESS；publisher 親核全部8套与 host1585/3。独立复算405 loaded源码哈希、库存和DA对b41相同，只有 transfer_service 1203异常处理既有行新增1命中（host16708/19349、transfer828/882），未降低原floor827，无旧命中丢失，19unknown保持。此测量不等同新f8。

Leader A 原文冻结 `4702ee5248cfdb3120225d3f71f8778de447e7c3`，只有36行新增文档，非作者范围复核通过。其 c265 时点的“AIUI-8/9未合”及Mac字体根因推断按历史保留，不采为当前完成/确诊结论。现状/账本/条件计划候选 `3bfdbbdcd8d17d32f8c7296ae97cc4ecb761e6d2` 已获非作者精确文档复审，最终集成仅更新当前证据；默认值和任何凭据、构建、设备安装或分发均未改变。

执行边界：用户另行删除已合远端分支；本批未重建旧分支、不prune或删除本地工作。唯一保留的review/aiui6-reg3b-integration-20261010固定f8，用户明确授权其全部提交进入develop、发布门禁通过且无活跃续写后删除；保留此commit与CI/审查链接供恢复，不扩大到任务分支。命令行Git/gh当前访问失败，现有连接器仍能读取精确develop指针；若用连接器正常FF，须先核最终树与受测f8除docs外相同、保留f8及Leader A4702祖先，再以expected_sha=a68、force=false推进，并亲查最终publisher终态。连接器读回不得写作git ls-remote成功。

边界：AIUI-6 只提供单个已保存 Inquiry 对象的有界只读快照，不代表报价聚合、预算总额、导入预览或对话壳已接线。REG-3b 验证真实研究文件、版本与宿主权限竞态及公开 knowledge.search 拒绝旧证据，保留 raw KnowledgeService.search 的既有缓存语义；不代表旧 QA hash 校验已全部迁移或 REST/Exchange/剩余写工具已完成。默认开关、真实模型、Android 和全场景验收均另设门槛。
