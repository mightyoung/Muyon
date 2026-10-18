# Muyon 开发现状与 Claude 独立交叉审查

快照：2026-10-18 02:47 UTC。对象：`mightyoung/Muyon`。本文件是只读审查任务，不是通过报告，也不是合入授权。

## 1. 当前结论与入口

- 已合入基线仍是 `develop@0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`；`main@cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` 未变
- 最新 Batch3 已完成并 STOPPED，全部 writer/build/test 停止，未合入 develop/main。A 在精确产品2f完成 Android双ABI/API24/JNI/ELF/APK/16KiB/zipalign/lint/AIDL与普通构建；B 在新组合d25完成Rust与分层反向验证
- 尚未关闭的是：组合d25的Android/package验收、stock gate/合同适配、新组合专用CI，以及真正Android设备生命周期。A2f的Android通过不能转记到d25
- 原始日志已持久上传，能够独立核查；APK/JAR/SO二进制只在完整本地归档，不能仅凭日志哈希假定已取得或重新检查二进制
- 两次历史时间相关失败的原因未明；旧宽泛inverse classifier曾误杀，已拒绝该标签并补精确证据。这是本次重点审查，不应被最后一次绿色掩盖

最短阅读顺序：

1. [Batch3 最新固定交接](https://github.com/mightyoung/Muyon/blob/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/LEADERB-HANDOFF-20261018-BATCH3.md)
2. [A 独立复审](https://github.com/mightyoung/Muyon/blob/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/leaderb-batch3-20261018/A-FINAL-REVIEW.md) / [B 独立复审](https://github.com/mightyoung/Muyon/blob/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/leaderb-batch3-20261018/B-FINAL-REVIEW.md)，读到末尾的最终增量，勿停在中途pending段落
3. [B验证代码与组合合同](https://github.com/mightyoung/Muyon/tree/687bed55b60f0794ca95cb8efd07798674b51bc4/docs/tasks/leaderb-batch3-b-validation-20261018/) / [Batch3 证据descriptor](https://github.com/mightyoung/Muyon/blob/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/LEADERB-BATCH3-20261018-EVIDENCE.json) / [原始日志包](https://raw.githubusercontent.com/mightyoung/Muyon/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/leaderb-batch3-20261018/RAW-EVIDENCE.tar.gz) / [日志索引](https://github.com/mightyoung/Muyon/blob/49d3f6030c4d3464d66b4b6421e5cc416aa36133/docs/tasks/leaderb-batch3-20261018/REMOTE-RAW-INDEX.json)
4. 历史背景：[Batch2](https://github.com/mightyoung/Muyon/blob/b53bcbf044240c8600ee95c61dacb5d2859bd147/docs/tasks/LEADERB-HANDOFF-20261018-BATCH2.md) / [RESUMED](https://github.com/mightyoung/Muyon/blob/6c724cee7a098869c077199bc3cae3cf31ff5535/docs/tasks/LEADERB-HANDOFF-20261018-RESUMED.md)。其“SDK许可未接受”“原始日志未上传”“组合未建立”等状态已由Batch3按对应范围更新
5. [v1.3.2 设计入口](https://github.com/mightyoung/Muyon/blob/0ab2c4f667681b9aacb017f8cd2eea6f576cf78e/docs/design/redesign-v1.3.2-20261014/README.md) / [PR85：REMORY候选文档](https://github.com/mightyoung/Muyon/pull/85)，固定head `34e388ee0c440ed191002067d7894c690a15610b`

## 2. 固定审查对象与源码等价边界

快照时已通过GitHub branches/tree/compare/Actions API回读。分支名仅定位，审查用完整SHA。

| 对象 | 固定SHA | 用法 |
| --- | --- | --- |
| develop | `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e` | 已集成基线 |
| main | `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` | 对照；不修改 |
| 产品2f / `lab/rust-native-read-leaderb-20261018` | `2fbdc13efd84cabf04623775f87e762cd0d08c11` | A实际构建source；比develop ahead103/behind0，未合入 |
| 组合d25 / `lab/leaderb-batch3-combined-20261018` | `d25a407830ef624802583983c0be2414bbd59dc4` | 本次B主审对象；tree `829f0d3d02bd5f8cf5f57ddef27f7fa4be3341db`；保留完整HTTP8e ancestry并加checker7481，无A验证或WIP |
| B验证 / `lab/leaderb-batch3-b-verification-20261018` | `687bed55b60f0794ca95cb8efd07798674b51bc4` | 50个文件仅在 `docs/tasks/leaderb-batch3-b-validation-20261018/`，含OUTCOME/RECOVERY/runners/contracts |
| Batch3归档 / `lab/leaderb-batch3-archive-20261018` | `49d3f6030c4d3464d66b4b6421e5cc416aa36133` | 最终交接、A/B复审及持久日志 |
| A验证代码 | `a0c14e13b700a57b92fabab19dd546a636da2741` | 在2f上仅加4验证文件；Batch3从外部提取，不改变A source |
| 前批HTTP8e | `8e0f6b1d0abfb0115bf48fa0bc8c790bfe30fa16` | 对照；前驱 `21acf36875da91c75157fddf6ef88e68c677a2ee` |
| 前批checker归档 | `b53bcbf044240c8600ee95c61dacb5d2859bd147` | checker代码 `7481ba0daf8954bb54139d2cf2a248edfd0ca5d0`；不单独包含A/B实现 |
| PR85 | `34e388ee0c440ed191002067d7894c690a15610b` | Draft文档候选；不是记忆实现 |

已独立通过Git tree API核对：

- `aa0bc2cf9527911c8764b8578ee706f3499fe82f`、`e612e37ddf82cb30a72c1d3aab1dfdce3e961055`、产品2f的 `android-compose-lab`、`android-rust-bridge-lab/core`、`core-agent-lab/core`、`plugin-contract-lab/core`、`rust-agent-host-lab/core` 五棵树相同
- 组合d25与HTTP8e的core/plugin/host三棵运行时crate树相同：依次 `97fc8c1d24e1834ca1f8319cc5614f16a1b66564`、`685e9ca45c33c9f9b8017d313da5f79bebd1c2a0`、`a718c296eee97f7dd1bc524408b85450102448a9`

这些只证明列明路径的源码字节相同，不证明整个仓库、checker、工具链、生成产物、参数或运行环境相同。旧aa0/e612结果不能改成exact2f重新执行；A2f Android结果不能外推至d25。B验证archive SHA也不是产品执行SHA。

## 3. 证据与未完成边界

下表是已回读的CI状态与固定交接/复审记录。本文件编写未新跑构建测试、未重新解包核验全量raw；Claude应对照原件独立复核，不把作者报告当结论。

| 范围 | 最新证据 | 不可外推 |
| --- | --- | --- |
| 产品2f Rust CI | [run39088023844](https://github.com/mightyoung/Muyon/actions/runs/39088023844) 精确2f completed/success；core/plugin/host required-full、required-native-inverses的job/step success；compiling-red按条件skipped | 不认证d25或本批重新构建的二进制 |
| PR85 CI | [run39087025974](https://github.com/mightyoung/Muyon/actions/runs/39087025974) 精确head34e388 completed/success，现有Flutter各包与Laya等通用CI | 不证明REMORY收益、CTX14或Rust HTTP门禁 |
| A本批 / exact2f | Linux Rust9/JVM5/load-negative1/panic1；API24 arm64/x86_64、JNI/ELF/import/16KiB；shipping Service JVM4变体、同次durable oracle及7负对照；package state163/AIDL/lint0错误6警告/6个native entries/zipalign；普通assembly clean与build均exit0、71 tasks | Android设备runtime仍NOT_RUN；Service3编译反向及独立Service Rust13本批未重跑；前批结果可引用但必须保留当时source/library身份 |
| B本批 / exactd25 | Core115/plugin22/host59；native3/HTTP7 baseline与inverse；legacy16精确Rust baseline0/mutant101/目标源码断言，加physical17真实ACK与目标失败；最终default-parallel core-full exit0，含process26/wire18/harness6+7/legacy17；144负对照，source/runner/binary完整性检查 | 使用明确标注的外置组合runner；不是stock gate通过、组合Android通过或专用远端CI通过 |
| 组合d25 CI | 快照时按精确head查询Actions：`total_count=0` | 不可继承2f、PR85或旧Compose run的绿色 |
| 仍未覆盖 | 组合d25 Android/package；stock inventory/anchor/exact8e pin适配；Android ART/Binder/UID/permissions/fsync/kill/rebind/device/emulator | 按具体组件/集成/发布范围阻断，不无差别停所有开发 |

必须保留失败：首轮Core在100ms idle下缺helper PID，第二轮Rust115过但wire escaped-pair/read_bound1超原5000ms总预算。最终新目录完整通过不能证明历史失败原因。旧宽legacy classifier将无关depth测试PID失败误标KILLED；该标签已拒绝，采用独立精确target/源码行/语义断言证据。初始runner provenance过期、audit元数据同名覆盖已保留并修正；直接空调用test_http不算覆盖，真实unittest discovery29才计入。

原始日志包：SHA256 `5d44399e51939d0ae74f98225a58c2295e3003fc37df9cb7b13cb2605f929cd1`，1,575,969 bytes、2408 files；含日志、manifest、合成捕获数据、source、review，不含编译应用。完整本地包SHA256 `5f5a2f3cb833bfb417c975ed3d0599f859931bbc25da8d9cca21957cf3f8bf1c`，34,261,359 bytes、2419 files，含APK/JAR/SO，未上传。先核包与索引，取不到的对象标未知；不能把整个批次误写为“无原始日志”。

A本批shipping库SHA256 `5010c537d4d52314c86e3bc9f9a4b04147d95f61e0eef8b1b16431a5bda84b97`；app APK `ad5bdca75a9e486c8b591fa8991656992ee1ed167936ddfdacfd571dd3b0f0af`；test APK `726500f8b3c92e861484b1ee713e56b5e2c1fc6dca18f0c73137150869f5d69f`。不能用Batch2旧库pin替代本批库。

环境前置已更新：用户批准并接受本云环境所需Google SDK协议2019-01-16版本，仅selected-package android-sdk-license；NDK28.2.13676358/r28c、Platform36 rev2、Build Tools35.0.0、Platform Tools37.0.1、CLI22.0，Rust1.99.0/JDK17/Gradle8.13。30个官方Android skills仅确认安装在对应云环境，catalog热刷新未确认，不推断其他机器已装；参考归档 `SDK-LICENSE-ACCEPTANCE.json`、`TOOLCHAIN-VERSIONS.json`、`ANDROID-SKILLS-INSTALL.md`、`RESTORE-TOOLS.md`。

## 4. 审查任务

每个方向先核实成立的能力与边界，再找缺陷。避免只列抽象风险；也不能用“实验代码”略过已承诺的安全合同。无需重写总体规划。

### A. 设计、功能与真实入口是否一致

- 以 v1.3.2 两册、迁移追踪和Android补充为设计输入，沿 `docs/tasks/redesign-kickoff-20261014/`、`docs/contracts/redesign-v1.3.2/`、`docs/tasks/REDESIGN-*` 找到具体合同及实现
- 分开列出正式 `apps/muyon` / 业务 packages、独立 `experiments/redesign/*`、文档候选、尚未执行的验收；核对研究/询价/供应商/资料与任务等现有功能是否确实接上新入口，不能以演示页面推断端到端完成
- 审查状态、错误/恢复、已有数据迁移与页面披露是否吻合；旧文档的“未执行”可被新固定证据更新，但不得凭较晚日期覆盖原证据缺口
- 已定 Auto / FullAllow 语义不重新辩论。只检查实现、权限边界与实际请求payload是否符合已定合同；发现实现违约仍需报告

### B. 核心 Agent 与真实模型的区别

入口：产品2f的 `core-agent-lab/core/src/{agent,agent_ports,host_session,model,policy,store,wire_provider,wire_sse,http_transport}.rs`；组合d25/前批HTTP8e对应差异；`rust-agent-host-lab/core/src/{lib,model_gateway,contract_transport}.rs`。

- 跟踪真实入口→Agent drive→当前authority/purpose/projection检查→模型gateway→工具执行→receipt→最终输出，而非只读fixture命名
- 分辨纯脚本、合成SSE、真实loopback socket I/O、trusted builtin handler与真实外部模型。哪些只是开发合同？哪些目前可由Android实际调用？离线通过不等于模型任务质量或联网产品就绪
- 检查单一预算、取消、deadline、撤权、晚回包、流式不完整参数、unknown、receipt优先级；是否存在第二套loop、authority或注册旁路
- 真实模型、密钥、远端endpoint、费用与模型效果没有本批验收依据。禁止自行填补为“已支持/已验证”

### C. HTTP预算、错误分类与跨进程不重发

重点：组合d25（与HTTP8e相同的运行时树）`core-agent-lab/core/src/agent.rs`、`host_session.rs`、`tests/native_runtime_restore.rs`；`rust-agent-host-lab/core/src/{lib,http_recovery_tests}.rs`、`tests/host_http.rs`；checks@b53 的 `http_batch.py` / `http_batch_inverses.py`，以及验证archive687bed中的组合contracts/runners。

- `wire_total_limit` 是否保持 `budget_exhausted/host_budget`；`wire_journal`、sent/failed账本写失败是否保持unknown；后来的cancel是否会覆盖unknown；计费是否复用已有total预算并持久化实际HTTP字节
- SharedSession错配必须在账本/admission/socket之前拒绝；native-host discriminator是否封闭，是否意外放松script/chat-sse恢复、伪造authority或接受非法正字节历史
- 分别核对首次进程真实I/O、真实退出、另一个进程打开原始目录、原task/attempt/计数与begin账本不变、连续drive仍不发provider、不新增连接。查看子进程退出码及目标断言，不以mock计数代替端到端证据
- `http_recovery_tests.rs`中的crash/sent-ledger/failed-ledger用新进程恢复；`wire_journal`用同进程post-I/O checkpoint失败。不要将后者声称为charge-time故障、ENOSPC或独立进程journal恢复
- 检查恢复前测试修复目录并还原原始账本的动作是否严格保持字节、是否掩盖不可恢复的生产状态；说明这种测试前置条件，不直接推断shipping自动恢复
- Legacy positive-wire host journal没有自动迁移；精确报告兼容性与阻断范围，不自行补迁移或重试

### D. Android retention / Service生命周期 / JNI与设备缺口

入口：产品2f的 `android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab/` 中 `AgentControllerRetention`、`AgentLivenessRegistry`、`AgentServiceClientState`、`AgentServiceRuntimeSupport`；app中的 `AgentRuntimeService`、`AgentServiceClient`、Binder/Proxy；host中的 `service_controller`、`service_root`、`service_runtime`、`service_evidence`；A的 `verification/shipping-service-20261018/`。

- 检查切页/Dispose/重建、快速重复请求、取消、client epoch/lease、可见性、retire与join；断开UI是否错误释放仍工作的controller；global slot及原root lease是否保持到真实Closed
- 检查panic后的原receipt/opaque/native bytes、deadline先于late cancel、账本失败优先unknown、保留不完整原子临时文件、同一请求dedup与冲突；同进程slot与跨进程flock必须分开
- 核对fresh bindings、实际映射的shipping library哈希、JNI/ABI与测试路径。A验证为新增4个文件，未改变产品2f；本批二进制与旧Service inverse library pin不同，不能混算运行SHA或库身份
- 明确区分A2f已过的API24两ABI链接、ELF/import、APK native inventory/16KiB/zipalign/lint/AIDL/普通assembly，与组合d25尚未执行的同类验收，以及仍NOT_RUN的ART/Binder/UID/permission/fsync/kill/rebind/device/emulator。lint为0错误6警告，不是零警告
- 设备缺口影响对应发布/产品验收，不无差别阻断独立Agent或其他已授权开发

### E. 插件schema与注册公共性

入口：产品2f `plugin-contract-lab/core/src/lib.rs`、`tests/{registration,read,mapping}.rs`；`docs/tasks/PLUGIN-PUBLIC-DATA-CLOSURE-20261018.md`；host的 `read_registry.rs`。

- 核实已有Catalog是否真正支持原子DATA/RELATION/read operation/view注册、authority过滤发现及schema闭包、prepare/invoke/accept_result、one-shot ticket、generation/current snapshot、host-owned receipt身份
- 外部DATA必须显式获host admission，包括所有可达foreign schema；版本不匹配、循环、漏传递依赖及失败后registry不变均需覆盖；metadata admission不等于read/model-export授权
- 检查research/inquiry/equipment是否经过同一公共合同，是否仍在host暗藏inquiry专用形状或固定匹配；区分通用元数据注册与可执行第三方插件/生产数据接入
- 不重复设计第二套注册系统；不要把trusted synthetic builtin证明成任意第三方插件安全

### F. CI、失效测试与反向测试能否揭穿错误

入口：`.github/workflows/{ci,core-agent-lab,rust-native-read,android-rust-bridge,android-compose-lab}.yml` 与各lab `checks/`。记录所读SHA。

- 对照branch/path过滤、job的if/needs、suite选择、测试inventory和实际日志；检查哪些新分支根本不会触发门禁。总体绿色不表示每个job执行，skipped必须按条件解释
- product2f的Rust workflow push仅匹配 `lab/rust-native-read-*`；Android bridge与Compose各有独立前缀。组合d25当前没有精确head run，不能继承产品2f或PR85的CI结论；stock gate会因原inventory/anchor/exact8e pin拒绝组合，不能把外置runner通过称作stock通过
- 检查每个反向变体先有精确baseline GREEN，再编译成功、在指定行为断言失败；timeout、编译失败、缺工具/fixture、强杀或残留子进程不能算KILLED
- 核对原17个语义inverse、native3、Service3、HTTP7的身份与各自source。定义仍存在不等于在新候选实际重跑；Batch2未在B8e0重跑，但Batch3已在d25补legacy17/native3/HTTP7；精确16对日志、physical17 ACK与失败断言、144负对照应单独复算，不能只信旧宽KILLED标签
- 检查是否删旧family、改RED期望、弱化断言、改变inventory/count以遮掩失败、把无环境时早退的helper算作行为覆盖、吞掉非零退出或用旧二进制过门禁。区别测试数量与独立行为数量
- 本批的PID文件ENOENT、escaped-pair时间预算失败、无关depth失败误杀、provenance过期和audit结果同名覆盖必须审查；区分已纠正的证据封存问题与仍未解释的测试不稳定。历史host48对旧46 inventory、mapper cwd与Service inverse缺文件也不能改称有效RED

### G. 研究候选的状态不能混入实现

- REMORY三项分别判断：结构化补充信息T、事务压缩P、神经soft-token N。先实验证明有效，再决定实施；当前文档与软件合同不等于模型收益
- PR85固定head的 `docs/design/remory-isolated-validation-20261018.md` 及相关候选文档是研究协议；CTX-T01–T14仍NOT_RUN、阈值尚未冻结；ContextContribution/生产memory未获本任务实施授权
- RSI top三臂小试无增益后用户已决定“不加”。不把这项研究重新包装成已实施模块、必做里程碑或新的集成阻塞；若引用实验细节，必须给原始来源，缺则说明未知

## 5. 输出要求

先给简短结论，再按 Critical / Important / Minor 列证据充分的发现。没有Critical就明确没有，不为填格夸大。每条至少包含：

1. 编号、级别、结论：成立 / 不成立 / 未知
2. 具体断言与影响；精确source SHA、文件路径和行号，优先用固定commit的GitHub permalink
3. 源码/日志/fixture/CI依据，实际观察与推断分开；测试执行SHA、artifact哈希、退出码、目标断言和证据缺失情况
4. 最小修复或最小补证步骤；不要直接改代码
5. 阻断范围：特定组件合入、组合候选、Android发布、真实模型验收或仅文档准确性；不要默认所有开发都停

附两个短表即可：

- 能力地图：已在develop / 独立候选已实现 / 仅有设计 / NOT_RUN / 未知，附入口及证据
- 建议验证：要验证什么、固定source、最小命令或步骤、预期目标断言、工具/日志/许可/设备前置条件。把建议与本次已执行严格分开

最后回答：当前最值得先修/补证的最多三件事是什么？哪些现有通过结论可靠，哪些表述过度？不要给一份替代开发路线图。

## 6. 操作边界与快速复制提示词

默认只读：允许读取源码/远端CI/原始证据，在不修改source或fixture的前提下静态核算现有记录与哈希；不要修改产品代码、提交、push、开PR、合入、部署、删分支、触发CI、接受许可、配置凭据或调用收费真实模型。需要新构建/反向变体/设备/模型运行时，先列建议验证和所需授权。所有集成仍由唯一LeaderB承担。

可用新的独立subagent并行审查不同方向，但保持短交接、固定输入、独立结论；不得启动第二个集成人。已有作者报告是待核查材料，不是审查结论。本批已STOPPED；后来如有新批次，须另取固定SHA与证据，不猜测完成状态。

复制给Claude：

> 请按本文件对 mightyoung/Muyon 做独立只读交叉审查。先核对固定SHA与远端状态，区分develop、A产品2f、B组合d25、验证archive687bed、最终归档49d及PR85文档候选；源码等价不等于同次运行。重点检查Agent真实链路与合成模型边界、HTTP预算/error/unknown跨进程不重发、Android retention/lease/receipt与JNI/device缺口、公共插件schema闭包，以及stock gate与外置runner差异、CI缺口、历史误杀和未明时间失败。核实Batch3已补的Android构建和legacy17/native3/HTTP7，不能沿用Batch2过期缺口。不要把作者报告当结论，缺原始日志标未知，建议验证单列。按Critical/Important/Minor给成立/不成立/未知、固定SHA文件行号、最小修复和阻断范围；附简短能力地图与前三项优先补证。Auto/FullAllow既定语义不重开，REMORY先证明收益后实施，RSI无增益已决定不加。本任务不授权修改、push、合入、触发CI、收费模型或新许可；唯一LeaderB负责集成。
