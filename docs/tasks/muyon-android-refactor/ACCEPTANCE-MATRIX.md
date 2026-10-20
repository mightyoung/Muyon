# Muyon Android 验收矩阵

核验日期：2026-10-21。验收规格：[36 场景](planning/muyon-android-refactor-tests-20261020.md)；执行范围：[21 张任务卡](planning/muyon-android-refactor-tasks-20261020.md)。本文件记录证据覆盖，不批准整体交付。

**整体结论：PARTIAL / FINAL_RUN_PENDING。** 目标候选为 `e6a1f3939c4ecba9741ac516add50022e7b7c0d2`，本轮读取时工作树 HEAD 与此一致。协调者正在对同一 APK/source 重跑；不得从本文件推断最终 18 方法全绿。I04 独立 HOLD，生产价格证明端口仍为 `None`，真实模型、搜索与模型工具后续调用均无本次 live 验收证据。

## 证据口径

- `LOCAL_PASS`：已有对应本地行为证据；不代表该行全部设备/live 条件通过。
- `PARTIAL`：该场景只有部分断言或层级得到证明；剩余项明确列出。未测不等于实现失败。
- `FINAL_RUN_PENDING`：当前候选最终设备运行及身份聚合待完成。早期通过、已修失败、测试文件存在均不能代替它。
- `BLOCKED_HOLD`：保留原阻断；不重试、拆分或更换入口规避。
- `LIVE_BLOCKED`：缺生产授权/价格证明或有效 live 证据；本地 fixture 不升级为 live PASS。

本地 Rust 全工作区日志有 **120 次通过执行、0 failed、0 ignored**；其中 `muyon-core` 的 15 个单元方法又以 `business_worker` 编译执行一次，**不能称 120 个独立用例**。数量也不等于 36 个复合场景全部满足。C01 的 24 项 Rust 子集已包含在这 120 次中，不再次累加；24 项离线 Kotlin 与 102 项旧 header/protocol 是另行报告的离线断言。

| 证据键 | 来源与能证明的范围 |
| --- | --- |
| E-CONTRACT | `crates/muyon-core/tests/contract.rs`，10 项；严格解码、规范化、revision、绑定、receipt 状态。设备差分是 `ContractCodecProductTest` 两方法，不能称全 fixture Kotlin 差分。 |
| E-BUSINESS | [存储证明](core-store/VERIFICATION.md)、[旧 schema 事件](core-store/SCHEMA-V2-INCIDENT.md)、`tests/business.rs`；当前全量日志 14 项。真实 SQLite、owner lock、两个 SIGKILL 窗口、原回执、CAS、引用规则及 schema 完整性。 |
| E-RESEARCH | [研究证明](research/VERIFICATION.md)、`tests/research.rs`；当前全量日志 16 项。目录/STORED ZIP 等价、真实私有 PDF、来源修订/引用/refresh、原始 metadata 与原子发布。 |
| E-FILES | [blob 证明](blobs/VERIFICATION.md)、[API26 固化修复](blobs/API26-SOLIDIFICATION-FIX.md)、[ZIP 证明](archive/VERIFICATION.md)。当前 core 单元 15 项含 blob 单元/资源验证；blob 集成 8 项、archive 13 项。历史 hardlink 结果不冒充当前 copy/fsync/rename 协议。 |
| E-FFI | `crates/muyon-android-ffi/src/lib.rs` 单元 5 项；纯预览/可见确认、原回执、初始化边界、回复有界及工具确认绑定。 |
| E-C01 | [独立审查](C01/FINAL-REVIEW.md)、[工具环路](C01/TOOLS-LOOP.md)、[实现及价格边界](C01/README.md)。审查结论 COMMENT、当前确认缺陷已修；owner/product/tools 为 11+6+7=24 项 Rust，最后独立 Kotlin 24/24。真实 SQLite/内存流，无 socket、真实凭据或付费请求。 |
| E-D01 | [D01](D01/README.md) 与 `D01/api26-final-instrumentation.log`；原实验 Settings→Send 两方法与成对失败/修复证据，不是新产品 live 链。 |
| E-CORE-DEVICE | `/private/tmp/muyon-product-api26-eighth.log` 实际 `OK (13 tests)`。这是最终重跑前的核心套件结果；最终 source/APK/native/selector manifest 由协调者补，不据此填写最终 PASS。 |
| E-PICKER | [真实 picker 记录](system-picker/VERIFICATION.md)、`SystemPickerProductTest.kt`。第四次 PDF 运行已实际选择文件到手填预览，随后零发布 matcher 失败；修后同候选重测待完成。目录、ZIP、源删除后重开须分别有结果。 |
| E-LOCAL-RUN | `/private/tmp/muyon-product-rust-all.log` 完整结果为 5+15+15+11+6+7+13+8+14+10+16=120 次 PASS；`/private/tmp/muyon-product-clippy-all.log` 完成。命令/exit/source 绑定与长期日志副本由协调者封存；临时绝对路径不是长期证据包。 |
| E-HEADER | `/private/tmp/muyon-product-header-102.log`：102 项离线协议检查通过，明确 no network/no real credential。 |
| E-GATE | `apps/muyon_android/checks/{instrumentation_gate,suite_gate,package_gate}.py`。本核验者亲跑 `python3 -m unittest discover -s apps/muyon_android/checks -p 'test_*.py' -v`，exit 0、2/2 PASS；包含 adb exit0 但失败/skip/缺数/缺 selector/重复结果的拒绝。尚不等于最终聚合实际通过。 |
| E-I04 | [状态](i04/STATUS.json)：既有证据只读审计 PASS，行为 NOT_RUN、BLOCKED，原受限恢复实验未执行；HOLD 未解除。 |

## 36 场景逐项映射

表内设备证据均为 provisional，最终设备列统一受 `FINAL_RUN_PENDING` 约束。相同测试可以支撑多个场景，不能重复计为新增测试。

| ID | 本地 / 设备 / live 状态 | 已有直接证据 | 未闭合的具体条件 |
| --- | --- | --- | --- |
| CT01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-CONTRACT；E-CORE-DEVICE 的实际 Kotlin→Rust NFC/emoji 与非法 UTF16/原始长度拒绝 | 设备仅选定向量；全部合同 fixture 的跨语言语义/digest 差分及大 revision 跨端往返未完整覆盖。 |
| CT02 | LOCAL_PASS / PARTIAL / 不适用 | E-CONTRACT、E-RESEARCH：手填与导入规则分离，project/upload/digest 绑定 | 最终 APK 的 PDF/目录/ZIP 入口和负例身份链待统一封存。 |
| CT03 | LOCAL_PASS / PARTIAL / 不适用 | E-CONTRACT/E-BUSINESS/E-FFI/E-C01；旧 scope generation、lease 关闭、取消/unknown/原回执各有局部测试 | 实际业务取消与 COMMIT 两顺序及设备在途写断联/重连未完整覆盖；已有旧 lease 测试不是该组合的全部证明。 |
| CT04 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | 严格版本/未知字段测试；schema1/缺表缺列拒绝；真实生成 Kotlin | 同候选生成字节、协议/业务/DB 版本及双 ABI/APK 最终身份门禁报告待封存。 |
| SU01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-BUSINESS；Supplier `visibleReviewCrudUsesActualReceipts` 及分页方法 | API26 专门重启后八字段/同名 ID 完整核对仍缺；合法最大 Unicode 完整 payload 的分页回复边界未专测。 |
| SU02 | LOCAL_PASS / PARTIAL / 不适用 | 精确原 intent 幂等、异参冲突、CAS、历史 receipt 与当前值分离 | 真 OS 进程同 intent/CAS 竞争和设备双击提交没有专门结果；owner 排他拒绝不能替代这些竞争断言。 |
| SU03 | LOCAL_PASS / PARTIAL / 不适用 | E-BUSINESS 旧引用保留/新引用拒绝；API26 删→恢复 revision 链 | 设备引用投影/拒绝、删改竞争及对应重启组合未完整覆盖。 |
| RE01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-RESEARCH；Research host PDF/真实详情及导入/分页；picker 项目创建流程 | 四项 picker 行为最终结果及同文库跨入口、跨项目设备负例待补；Rust 跨项目拒绝已有。 |
| RE02 | LOCAL_PASS / PARTIAL / 不适用 | 目录与真实 STORED ZIP 等价；重复/引用修订/refresh 原子语义；API26 DEFLATE host provisional PASS | 实际系统目录与 ZIP 同内容导入结果比较及重启核对尚无最终结果。 |
| RE03 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | 手填校验/真实私有 PDF/重复 intent 本地证明；设备 host 实际 PdfRenderer | 真 picker→完整手填→可见确认→附件重开最终待跑；设备 PDF 草稿取消不发布没有单独方法。 |
| RE04 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01：真实 DB supplier/paper 只读、scope 撤销、删项排除、独立外发披露与工具后续计划 | 模型返回工具请求与真实产品后续请求的 live 链未执行；设备工具披露/建议确认 UI 无完整结果。 |
| DB01 | LOCAL_PASS / PARTIAL / 不适用 | 显式初始化、缺库不建、schema/锁/坏库/constraint 类型、旧 pending 保留 | 磁盘满/写失败注入及所有锁类与 IO 类错误区分未完整覆盖。不得把 StorageIo 修复等同磁盘满测试。 |
| DB02 | PARTIAL / PARTIAL / 不适用 | 真 SQL 后 SIGKILL 回滚、receipt 尾破坏回滚、COMMIT 后丢回包查原结果 | history 后、intent 终态后等每个指定故障点尚非逐点独立测试；已有回滚测试不推出每点全覆盖。 |
| DB03 | PARTIAL / PARTIAL / 不适用 | 真 owner 跨进程排他、SIGKILL 释放、新 epoch 重开、物理 SQL 独立观察 | 同 intent 与 CAS 的不同 OS 进程竞争未完整验证。 |
| DB04 | PARTIAL / PARTIAL / LIVE_BLOCKED | E-BUSINESS 撤权先 COMMIT barrier、过期/epoch；E-C01 预算 reservation/claim SIGKILL 与不重发 | 业务授权复验后/COMMIT 前与撤权/取消两顺序完整 barrier 矩阵、业务提交且 admission 未结算的组合缺。网络 send-gate 两顺序不能替代业务库 COMMIT 两顺序。 |
| FS01 | LOCAL_PASS / PARTIAL / 不适用 | archive/research 路径、重复/冲突、坏元数据/JSONL、上限规则负例 | 30MiB/150MiB/10000 文件恰好与超一边界及真实 SAF provider 恶意/撤权输入未全部执行。 |
| FS02 | LOCAL_PASS / PARTIAL / 不适用 | E-FILES 当前 copy/rename 十二故障窗口与真实 PaperCreate 两进程故障；单事务引用/receipt | API26 未逐点执行跨介质终止窗口；不得称 Android 全故障窗口通过。 |
| FS03 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-FILES reader/upload pin、GC barrier、deleting/损坏/缺文件；E-RESEARCH 删除源文件后私有 PDF 读 | 系统原 PDF 删除后新 Activity 再读的最终 picker 方法待跑；源 URI 授权主动撤销的设备负例缺。 |
| AR01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-FILES ZIP32/Dart round-trip/descriptor/CRC/offset 负例；API26 DEFLATE host provisional PASS | 最终真实 picker ZIP 链待跑；同输入重复平台读取及规模资源设备测量不由单次成功推出。 |
| RC01 | BLOCKED_HOLD / BLOCKED_HOLD / 不适用 | E-I04 只读状态/哈希审计 | 原合同运行证据缺，明确 NOT_RUN；不在当前本地补测清单中重做该受限实验。 |
| RC02 | LOCAL_PASS / PARTIAL / 不适用 | Rust supplier/paper/agent SIGKILL 原回执；ProductRecovery 实际已提交后杀 Service、新 epoch 原回执和拒绝旧 plan | 尚无设备 business confirm 已发但未收到回包时杀进程、持久 UI 原 intent 再恢复的完整窗口。已收到 committed 后杀进程是不同窗口。 |
| AN01 | PARTIAL / FINAL_RUN_PENDING / 不适用 | 真实 API26 ARM64；Unicode 异常后同进程 owner 重开、饱和 close、lease 关闭、Service 死亡 | 最终双 ABI 打包/运行 build ID/SDK/对齐聚合待封存；x86_64 没有实际运行证据，交叉构建不能冒充运行。 |
| AN02 | LOCAL_PASS / D01_TARGET_PASS / 不适用 | E-D01 原两 Settings→Send 方法、失败→修复 | 限定复用原实验目标，不推出新产品真实普通发送/搜索成功；新产品链由 AN07/CH02–04 单列。 |
| AN03 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | 实际 Compose→Service→Rust→SQLite CRUD、删/恢复、预览无写和分页 | 最终重跑待完成；重启八字段与设备引用规则专门组合仍缺。 |
| AN04 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | API26 平台 DEFLATE host 与 CRC 拒绝 provisional PASS；真实 ZIP/目录 picker 两方法已编写 | 必须获得两方法实际成功、来源/附件与物理数据一致及重启结果，不能以 host 测试替代系统 picker。 |
| AN05 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | picker PDF 实际选中到预览；host 私有 PDF 详情/渲染已有 provisional PASS | 修后 publication matcher、完整可见保存、删除源后私有 PDF 再开最终待跑；取消 PDF 草稿专门结果缺。 |
| AN06 | LOCAL_PASS / PARTIAL / 不适用 | 实际返回预览保留草稿、真实旋转丢未确认草稿且零写、关闭 lease 抑制陈旧 prepare 回调、饱和 close、已提交杀 Service | 双击真实确认、确认中旋转/杀进程、业务取消与 COMMIT 竞态、UI 持久 unknown 恢复未完整覆盖。 |
| AN07 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | C01 owner/transport/本地工具/可见预览和后续请求实现与离线测试；价格证明缺失时设备边界方法 | 真实模型答案、真实搜索和 live 模型工具→业务读取/写建议→披露→后续请求未执行。不能称 C01 未实现，也不能称 live 完成。 |
| CH01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-HEADER 102 旧协议离线检查；E-C01 修复后本地 transport/runtime 检查 | 同候选 Android rebuild/lint/设备身份汇总待补。历史 unknown 的确切原因仍不据这些本地结果断言。 |
| CH02 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01 accepted/schema/usage/history、本地单次派发及同会话边界 | 生产 HostedCostVerifier 未绑定，真实普通发送/连续发送/accepted answer/usage 未执行。 |
| CH03 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01 现存 SearchProvider 解码、空/非空结算、错误保留 unknown 的 fixture | 生产 SearchPriceVerifier 未绑定，真实外部来源及 live 空结果/错误未执行。 |
| CH04 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | SQLite 累计预算/attempt/unknown 保留；Kotlin send-gate 两顺序；取消/重开/会话撤销；设备缺证明拒派发 | live 有效授权/价格证明及实际外发取消/恢复未验证；旧 unknown 账与 I04 不变。 |
| PK01 | PARTIAL / FINAL_RUN_PENDING / 不适用 | 当前双 ABI native 生成/包装检查脚本存在，已实际构建；E-FFI 生成绑定 | 最终 producer 状态、生成字节、两 ABI/APK 库 digest/SDK/对齐、build ID 与 e6a1f393 的不可混用 manifest 待协调者补齐。 |
| PK02 | PARTIAL / FINAL_RUN_PENDING / 不适用 | 独立 product package/business-v2 命名空间；默认缺 proof 拒派发，无 fixture 生产兜底 | 最终 APK 路径与库身份/工具链封存待补；schema-v1 旧未知数据必须继续保留。 |
| OR01 | LOCAL_PASS / FINAL_RUN_PENDING / 不适用 | E-GATE 本核验者 2/2 PASS，包括 adb exit0 但失败/skip/缺失/重复拒绝 | 最终 18 方法 inventory、各 selector 实际日志及 adb exit 的内容门禁实际运行待协调者收集，不能只凭单元绿。 |
| OR02 | PARTIAL / FINAL_RUN_PENDING / LIVE_BLOCKED + HOLD | 本矩阵保持 source 与层级分离；最终 suite gate 对全部方法缺失/重复做拒绝 | 最终候选设备聚合、长期原始日志/哈希待补；即便 18 方法全绿，RC01 与 live 门禁仍不满足整体完成。 |

## 当前设备方法清单（18，含 1 个 setup）

最终 suite manifest 应从同候选测试源码枚举，以下为本轮读取的清单。核心组 13 个方法已有 provisional 全绿；picker 组 5 个方法必须按其验证文档顺序单独运行，`generatePickerInputs` 只生成输入，**不是第五项业务验收行为**。两组的最终状态均为 `FINAL_RUN_PENDING`。

| 测试类 | 方法 |
| --- | --- |
| ContractCodecProductTest | `malformedUtf16AndRawLimitCannotTurnIntoAValidReviewedPlan`；`actualKotlinToRustCodecPreservesPairsAndUsesTheSameNfcRule` |
| ProductRecoveryTest | `closingWithAllRequestSlotsBusyStillRevokesTheLiveBinderLease`；`actualServiceDeathChangesEpochAndOnlyOriginalReceiptRecovers` |
| ProductLifecycleTest | `backFromReviewThenRealRotationDiscardsUnconfirmedDraftWithoutWriting`；`closingLeaseBeforePrepareReplyCannotReportStaleSuccessOrPublishSupplier` |
| ProductChatBoundaryTest | `explicitConfigurationCannotTurnMissingPriceProofIntoOutboundAuthority` |
| SupplierProductTest | `visibleReviewCrudUsesActualReceipts`；`dismissingReviewKeepsDraftAndDoesNotWrite`；`elevenRealSuppliersAreReachableThroughNextPage` |
| ResearchProductTest | `projectVisibleReviewThenActualPdfHostAndDetail`；`deflatedZipUsesFrozenArchiveAndSealsActualImport`；`corruptStoredMemberCannotPublishSnapshotOrPaper` |
| SystemPickerProductTest | `generatePickerInputs`（setup）；`pdfSystemPickerManualReviewAndPrivateAttachment`；`zipSystemPickerReviewAndImport`；`directorySystemPickerReviewAndImport`；`reopenPrivatePdfAfterOriginalRemoved` |

## 仍可本地执行的具体缺口

以下是证据缺口，不据此断言实现必然错误。它们与 I04/live 阻断分开，不能统一写成“都等待外部条件”。优先完成正在运行的同候选设备验收，再由协调者按 required 合同决定补测。

1. **完整 Kotlin/Rust 合同向量差分**：当前两设备 codec 方法只覆盖选定 Unicode/原始长度；同 fixture 的所有字段、digest、大 revision、边界负例仍需逐向量证明（CT01/CT04）。
2. **存储专项故障**：磁盘满/写失败、history/intent 终态等指定 SQL 点，跨 OS 进程同 intent/CAS 竞争，撤权与取消相对业务 COMMIT 两顺序；现有 owner-lock、两个 SQL kill 点和网络 send-gate 不替代这些断言（DB01–04）。
3. **业务已 commit、admission 未结算的组合恢复**：独立业务/agent 账都有测试，但跨组合零重发/查原事实还没有端到端本地 fixture（DB04/RC02）。
4. **产品 UI 在途写恢复**：真实双击确认、confirm 发出但回包未达时旋转/杀进程，重建 UI 后仅查询持久原 intent；现有预览旋转、prepare-close 和已收到 committed 后杀 Service 只覆盖相邻窗口（SU02/AN06/RC02）。
5. **规模与分页边界**：现有十一项翻页是小样本；最大合法 Unicode supplier 完整字段返回、10000 文件边界、30MiB/150MiB 恰好和超一及 APK 上有界资源行为仍有缺口（SU01/FS01/AR01）。
6. **完整研究 UI 负例与持久性**：PDF 草稿取消、真实 URI 授权撤销、目录/ZIP 等价数据最终比对、设备跨项目拒绝、supplier 重启八字段和引用规则组合；真实 picker 源文件删除重开已有专门方法，待最终结果，不另重复发明替代（RE01–03/FS03/AN03–05）。
7. **设备模型工具对话框本地边界**：工具披露、建议可见确认、会话/项目切换撤销的 Android 真实组件组合目前仅离线协调器/SQLite 证明；可以有无网络拒派发与权限负例，但它们不能升级为 live 模型工具链（RE04/AN07）。

## 更新与停止条件

本轮仅创建此文档，未运行 Gradle、adb、网络、凭据或付费调用，未改源码/测试或其他作者文件。后续协调者应附最终同候选 suite/package 结果、命令/exit/count/设备与哈希，并逐行更新对应证据；保留先前失败和修复经过。若 18 方法通过，只能关闭这些方法实际证明的设备断言，不能把复合场景全部或 I04/live 自动改为 PASS。真机、发布、历史 Flutter 数据迁移不在本次要求内。
