# AUTH-1b 审查记录

本轮范围仅 A。leader B 于 2026-10-08 根据独立 Mac 复核 APPROVE/CLEAR 与 exact SHA CI success 批准 A 集成；B/C 尚未验证。以下为独立报告摘要与核对表，原始运行日志、故障探针和变异驱动不入库。文档提交和 develop 集成结果仍分别检查新 HEAD CI 与 postmerge CI，不用旧绿灯替代。

## A 独立审查

目标：task/auth-1b-wiring@994cd6f2fde0841996adaf83c9ce3fee5a16200f；基线：965d9130d15379476d8f4ac3bacb830d61be16df。
执行位置：git archive 独立副本 /tmp/auth1b-independent-994cd6。原工作区只读；没有创建/修改实施分支、提交、push、merge。原始日志、探针、变异驱动均留 /tmp。

范围：18 个变化文件，符合 docs/tasks/AUTH-1b.md 的 A；五个既有测试适配仅显式列名、保留历史10/11目标或更新现行版本，未放宽业务断言。已核 ADR-0002/0004/0005 与 docs/tasks/REVIEW.md；采用 code-review 技能的独立 code-reviewer/architect 两线，均有独立静态证据，后者还独立计算冻结 SQL 指纹。

### 结论

具体代码 bug：0；CRITICAL/HIGH/MEDIUM/LOW：0/0/0/0。code-reviewer APPROVE；architect CLEAR。仅对 A 的范围批准；exact CI success 门禁亦已满足，建议集成 A。未执行集成操作。

| 核对项 | 结论及证据（目标提交相对路径/行） |
| --- | --- |
| migration11 不变；12登记与独立审查事实 | 满足。grant_store.dart:17–51 的 DDL 两提交完全相同；workspace/workspace_repository.dart:159–160 登记11/12；platform/grants/authorization_links.dart:15–45 只增加独立审查表、四表 nullable 关联与审批绑定，不改变 transport CHECK |
| 历史兼容与审计保留 | 满足。platform/host_schema_compatibility.dart:19–49,154–219 扩12目标/指纹；旧冻结夹具未改。磁盘 legacy8/9/10、canonical9、historical repaired10/11 到12升级和重开，逐列保留旧审批/回执/两类账本/授权审计；DDL 后失败与两类元数据失败整体回滚。专项实际通过 |
| 显式 INSERT 列名 | 满足。platform/tool_registry.dart:341,511,685–696；人工审批/read/effect/replay回归通过 |
| 消费+used审计+审批同事务 | 满足。tool_registry.dart:441–527；grants/grant_store.dart:153–164 核 owner transaction，无嵌套 write；审批 INSERT trigger 故障回滚；独立 used audit trigger 故障回滚并成功重试 |
| 最后一次竞争、once自己消费 | 满足。grants/grant_store.dart:170–175；专项双竞争+独立32竞争均只一份审批/一次used/一次效应；忽略限额变异签出两份审批而失败；恢复审批次数检查变异报 grant_invalidated 而失败 |
| 撤销/到期/绑定/重放 | 满足 A 的接口边界。tool_registry.dart:601–618,657–678；grant_store.dart:180–200 撤销同步本机阻断，失败不移除。专项实际 effect 断言，独立 revoked audit failure 保持本机阻断并可重试撤销 |
| 修订 fence | 满足。tool_registry.dart:427–455 解析前取样+消费队列内复核，:601–608 handler 效应前复核。效应 await barrier 实测；移除效应前 fence 后实际 succeeded、预期 failed，行为杀死 |
| A/B/C 边界 | 满足。没有 Agent 自动授权或 transport 自动许可接线；真实持久污染、review后复核、端点 identity 提供、模型取消订阅仍属 B/C |

### 本轮实际验证（非转述实施记录）

- flutter analyze --no-pub --fatal-infos --fatal-warnings：No issues found!；变异恢复后复跑同样通过。
- 两份 A 专项：+48: All tests passed!（/tmp/auth1b-independent-special.log）。
- 四个新独立 probe：+4: All tests passed!（/tmp/auth1b-independent-probe.log）。探针源码 /tmp/auth1b-independent-fault-probe.dart，基于专项真实host harness，新增32竞争、used审计失败、running回执失败、revoked审计失败，均断言数据库状态和实际handler计数。
- 五个历史适配文件+assistant_grants_test/tool_registry_test：+110: All tests passed!（/tmp/auth1b-independent-regression.log）。
- 独立三项变异均 exit1，均为行为失败而非编译失败：effect-fence（实际succeeded），last-use（实际两份审批），once-self-count（grant_invalidated）。日志 /tmp/auth1b-independent-mutation-{effect-fence,last-use,once-self-count}.log。未声称重跑实施者全部10项。
- 全部18变化文件恢复后与git show目标内容逐字节相同。
- 宿主全量：+938 ~3: All tests passed!（/tmp/auth1b-independent-full.log）。三个跳过项原样保留。
- exact CI37712788987：headSha精确匹配；completed / success，job ci 用时9m34s，Analyze and test every package与Laya script tests均success。最终JSON /tmp/auth1b-independent-ci.json，等待记录 /tmp/auth1b-independent-ci-watch.log；https://github.com/mightyoung/Muyon/actions/runs/37712788987。

### 限界

以上只证明 A 接口与受测宿主harness。handler 必须在真实写入/发送前调用 checkBeforeEffect / checkAuthorization / ToolCallContext.write，可信scopeRevision必须覆盖全部修订/工作区/可见性变化；A未提供真实消费者，不把测试常量当生产维护证明。撤销写失败的同步阻断是当前GrantStore实例本机内存事实；持久写失败跨进程不保证。没有真机/真实网络/模型流式取消与端点凭据运输验证。没有把未运行的实施者10项变异说成本轮结果。CI全部package验证与本机host验证分别记录。
