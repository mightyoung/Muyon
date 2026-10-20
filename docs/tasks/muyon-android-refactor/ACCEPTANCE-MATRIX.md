# Muyon Android 验收矩阵

核验日期：2026-10-21。验收规格：[36 场景](planning/muyon-android-refactor-tests-20261020.md)；执行范围：[21 张任务卡](planning/muyon-android-refactor-tasks-20261020.md)。本文件记录证据覆盖，不批准整体交付。

**整体结论：PARTIAL；当前候选产品设备套件 21/21 PASS，包装门禁 PASS。** 目标候选为 `7b063cb4089fe21fdaf82657bcf00408e3f138b1`，本轮读取时工作树 HEAD 与此一致。已读取持久化 `product-device/final/{SUITE,SUITE-MANIFEST,PACKAGE}.json`，并独立重跑同候选 suite gate：21 方法全部通过（核心 16＋picker setup 1＋PDF/ZIP/目录/源删除后私有再开 4），4 项门禁单元测试通过。早期候选及测试调试失败记录保留为历史，不混入这轮通过。I04 独立 HOLD，生产价格证明端口仍为 `None`，真实模型、搜索与模型工具后续调用均无本次 live 验收证据。

## 证据口径

- `LOCAL_PASS`：已有对应本地行为证据；不代表该行全部设备/live 条件通过。
- `PARTIAL`：该场景只有部分断言或层级得到证明；剩余项明确列出。未测不等于实现失败。
- `DEVICE_PASS` / `PACKAGE_PASS`：当前固定候选指定方法/包装证据已通过，不意味着该行所有复合条件、真实 provider 或整份改造计划全部通过。
- `BLOCKED_HOLD`：保留原阻断；不重试、拆分或更换入口规避。
- `LIVE_BLOCKED`：缺生产授权/价格证明或有效 live 证据；本地 fixture 不升级为 live PASS。

本地 Rust 全工作区日志有 **127 次通过执行、0 failed、0 ignored**；其中 `muyon-core` 的 15 个单元方法又以 `business_worker` 编译执行一次，**不能称 127 个独立用例**。新增为 store 3、resource 3、shared-vector 1；32 条共享向量是一个 Rust 方法内的断言。C01 的 24 项 Rust 子集已包含在这 127 次中，不再次累加；24 项离线 Kotlin 与 102 项旧 header/protocol 另报。

本核验者实际比对 `4faee9dc:crates` 与 `HEAD:crates`，均为 `c0bcc4306721dc39f75062c078319ec87931f1fa`；`git diff 4faee9dc HEAD -- crates experiments` 无输出。因此 4faee9dc 的 127 次 Rust 结果可沿相同 Rust 树追溯至当前候选，而不是把不同 Rust 内容的通过合并。Android 测试变更仍要求当前候选重新运行。

| 证据键 | 来源与能证明的范围 |
| --- | --- |
| E-CONTRACT | `tests/contract.rs` 10 项及 `tests/contract_vectors_additional.rs` 1 项；同一 `docs/contracts/muyon-android/fixtures/codec-vectors.json` 的 32 向量真实走 Rust 与设备 Kotlin→Service→Rust。设备检查精确错误、零 plan/零写、大 revision 字符串和唯一八字段确认后 Service 重开原 receipt；不声称 Kotlin 独立重算 digest。 |
| E-BUSINESS | [存储证明](core-store/VERIFICATION.md)、[补充 DB01–04](core-store/ADDITIONAL-GATES.md)、[旧 schema 事件](core-store/SCHEMA-V2-INCIDENT.md)。business 14 项加 store 3 项：真实四处 SQL 拒写、OS 子进程 RLIMIT_FSIZE 写失败、OS owner 竞争后的原 intent/CAS 核对，保留实际模型下的单 owner 约束。 |
| E-RESEARCH | [研究证明](research/VERIFICATION.md)、`tests/research.rs`；当前全量日志 16 项。目录/STORED ZIP 等价、真实私有 PDF、来源修订/引用/refresh、原始 metadata 与原子发布。 |
| E-FILES | [blob 证明](blobs/VERIFICATION.md)、[API26 固化修复](blobs/API26-SOLIDIFICATION-FIX.md)、[ZIP 证明](archive/VERIFICATION.md)、[资源补充](archive/RESOURCE-BOUNDARIES.md)。core 单元 15、blob 集成 8、archive 13、resource 3。真实 30MiB 正/超一、实际聚合 150MiB 封存正/超一、ZIP metadata 10000/10001；不等于 10000 实际上传封存或 150MiB ZIP 解压。 |
| E-FFI | `crates/muyon-android-ffi/src/lib.rs` 单元 5 项；纯预览/可见确认、原回执、初始化边界、回复有界及工具确认绑定。 |
| E-C01 | [独立审查](C01/FINAL-REVIEW.md)、[工具环路](C01/TOOLS-LOOP.md)、[实现及价格边界](C01/README.md)。审查结论 COMMENT、当前确认缺陷已修；owner/product/tools 为 11+6+7=24 项 Rust，最后独立 Kotlin 24/24。真实 SQLite/内存流，无 socket、真实凭据或付费请求。 |
| E-D01 | [D01](D01/README.md) 与 `D01/api26-final-instrumentation.log`；原实验 Settings→Send 两方法与成对失败/修复证据，不是新产品 live 链。 |
| E-CORE-DEVICE | [最终 CORE 原始日志](product-device/final/CORE.log) 与 [最终 suite](product-device/final/SUITE.json)：核心 16 方法实际全绿；含共享 32 向量、八次同 PID owner 交接及真实 commit 后丢 callback 的 UI 原 receipt 恢复。与 picker 统一由同候选 manifest 绑定。 |
| E-PICKER | [最终 manifest](product-device/final/SUITE-MANIFEST.json) 中五个 picker log 分别通过。真实 PDF 系统选择→预览取消零发布→重新选择填六字段→可见保存→打开私有 PDF；真实 ZIP/目录选择与导入；删除唯一指定原 PDF 后新 Activity 打开私有副本均实际 PASS。setup 仅生成测试输入，不当作第五项业务行为。早期失败见 [过程记录](system-picker/VERIFICATION.md)。 |
| E-LOCAL-RUN | `/private/tmp/muyon-product-rust-all.log` 5+15+15+11+6+7+13+8+14+10+1+16+3+3=127 次 PASS；`/private/tmp/muyon-product-clippy-all.log` 完成。Rust tree 绑定见上；命令/exit 与长期日志副本由协调者封存。 |
| E-HEADER | `/private/tmp/muyon-product-header-102.log`：102 项离线协议检查通过，明确 no network/no real credential。 |
| E-GATE | `apps/muyon_android/checks/{instrumentation_gate,suite_gate,package_gate}.py`。本核验者最终亲跑 `python3 -m unittest discover -s apps/muyon_android/checks -p 'test_*.py' -v`，exit 0、4/4 PASS；并亲跑 `suite_gate.py` 校验持久 manifest 与当前测试源码，exit 0、21/21 PASS。包含 adb exit0 但失败/skip/缺失/重复、替换仍显示 passing 的日志、不同 source/APK/run identity 的拒绝。 |
| E-RECOVERY | [owner 交接](product-device/SERVICE-OWNER-HANDOFF.md)、[真实 callback 丢失](product-device/UNKNOWN-REPLY-RECOVERY.md)、对应 ProductRecovery/ProductUnknownRecoveryTest 源码及当前 16 方法日志。独立 Android SQLite 读到 committed 后才 close sender，原 callback 为 unknown；kill Service 后 Supplier 与 Assistant 分别查询同一原 receipt，revision/history=1。文档最初的 pending 表述是先前检查点，当前核心运行已通过。 |
| E-PACKAGE | [最终包装](product-device/final/PACKAGE.json) 当前 `gate:PASS`，build_id 为 `7b063cb4089fe21fdaf82657bcf00408e3f138b1:e3e140e4584aff5a9bb8de35162e5fc42bb6e1318e96ec14d5c996c97013aaf0`；APK SHA256 `30693b01e27dc67d5a8c391ff327707b7ee46086dd9f5bf3fef6c847e5ab6173`，test APK SHA256 `5e3fb515b6e48e9d5548773de23d521db3783151499eb3cca88a2503c92fcc49`；生成 bridge/双 ABI 库 hash、16384 LOAD 对齐均在结果。manifest 每个 run 绑定 build/APK/test APK/log SHA256，保留 adb exit 0、SDK26/arm64-v8a。 |
| E-I04 | [状态](i04/STATUS.json)：既有证据只读审计 PASS，行为 NOT_RUN、BLOCKED，原受限恢复实验未执行；HOLD 未解除。 |

## 36 场景逐项映射

表内已执行设备方法引用最终同候选 21 方法通过记录；复合场景未覆盖的条件仍逐行保留。相同测试可以支撑多个场景，不能重复计为新增测试。

| ID | 本地 / 设备 / live 状态 | 已有直接证据 | 未闭合的具体条件 |
| --- | --- | --- | --- |
| CT01 | LOCAL_PASS / DEVICE_PASS / 不适用 | E-CONTRACT：32 个同源向量真实运行、精确错误/未发布，八字段确认与重开，大 revision lossless；另 codec NFC/emoji/非法 UTF16 | 本次共享向量门禁已补齐；不额外声称全部可能 Unicode 输入穷尽或 Kotlin 独立 digest 算法差分。 |
| CT02 | LOCAL_PASS / DEVICE_PASS（已测路径） / 不适用 | E-CONTRACT、E-RESEARCH 与真实 PDF/ZIP/目录 picker：手填/导入分离、private upload/digest、source/local ID | 系统 provider 恶意/跨项目的全部设备负例没有穷尽；已有 Rust 负例不混称设备逐项运行。 |
| CT03 | LOCAL_PASS / PARTIAL / 不适用 | E-CONTRACT/E-BUSINESS/E-FFI/E-C01；旧 scope generation、lease、取消/unknown/原回执；E-RECOVERY 真实丢 callback 恢复 | 精确业务 COMMIT 两侧撤权/取消调度仍有公开测试 seam 可达性限制；已补 callback 丢失，不再列该项缺失。 |
| CT04 | LOCAL_PASS / PACKAGE_PASS + DEVICE_PASS / 不适用 | 严格版本/未知字段、schema1/缺表缺列拒绝；E-CONTRACT 同源向量；最终生成 bridge/双 ABI/APK/runtime 身份 | 证明当前协议/业务/DB 与固定候选；不推断未来版本兼容。 |
| SU01 | LOCAL_PASS / DEVICE_PASS / 不适用 | E-BUSINESS；真实 UI CRUD/分页；共享向量唯一八字段确认后 Service 重开全字段及原 receipt 核对 | 合法最大 Unicode 完整 payload 的分页回复组合边界未专测；不再列重启八字段为缺口。 |
| SU02 | LOCAL_PASS / PARTIAL / 不适用 | E-BUSINESS+补充 store OS 竞争：owner 拒绝、后继 owner 原 intent 单效果与 stale CAS 拒绝；E-RECOVERY revision/history=1 | 同时被准入的两合法写 owner 在产品 flock 下不可达；设备真实确认按钮双击专门断言仍未覆盖。 |
| SU03 | LOCAL_PASS / PARTIAL / 不适用 | E-BUSINESS 旧引用保留/新引用拒绝；API26 删→恢复 revision 链 | 设备引用投影/拒绝、删改竞争及对应重启组合未完整覆盖。 |
| RE01 | LOCAL_PASS / DEVICE_PASS（已测路径） / 不适用 | E-RESEARCH；真实空库新项目、PDF 手填/导入文库、论文详情/私有 PDF；Rust 跨项目拒绝 | 设备跨项目拒绝及同一项目混合多入口的完整组合未单独穷尽。 |
| RE02 | LOCAL_PASS / DEVICE_PASS（平台入口） / 不适用 | 目录/真实 STORED ZIP 等价；重复/引用修订/refresh 原子语义；API26 平台 DEFLATE host 与真实目录/ZIP picker 均通过 | 真实设备两入口同一项目导入的物理数据逐项等价/refresh/引用组合不由两个独立成功流程直接推出。 |
| RE03 | LOCAL_PASS / DEVICE_PASS（实际 PDF 路径） / 不适用 | 真实 picker 选 PDF、草稿取消零发布、重新选择填全部六字段、确认前零发布、可见确认、私有 PDF 打开；本地重复 intent/附件命名保护 | 设备大批同名附件/非法元数据组合未穷尽；不自动联网为现有封闭文件路径，未将其当 OCR 或自动元数据识别。 |
| RE04 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01：真实 DB supplier/paper 只读、scope 撤销、删项排除、独立外发披露与工具后续计划 | 模型返回工具请求与真实产品后续请求的 live 链未执行；设备工具披露/建议确认 UI 无完整结果。 |
| DB01 | LOCAL_PASS / PARTIAL / 不适用 | 初始化/缺库/schema/锁/坏库/constraint；补充实际 OS child RLIMIT_FSIZE=0 触发 SQLite StorageIo，物理 SQL 零业务/零 receipt | 精确 SQLITE_FULL 尚未执行；公共 API 无同连接 max_page_count seam，不填满共享磁盘。OS 实际写失败已补，不能再泛称无写失败证明。 |
| DB02 | LOCAL_PASS / PARTIAL / 不适用 | 真 SQL 后 SIGKILL、receipt 尾破坏；四处真实 SQL RAISE(ABORT)：pending、supplier history、business history、committed intent/receipt；COMMIT 后丢 callback | 按点 SQL 拒写/回滚已有；每个 native flush 的 VFS/断电注入未做，不将其伪装成精确逐 syscall 故障证明。 |
| DB03 | LOCAL_PASS / PARTIAL / 不适用 | 真实跨 OS 进程 barrier 竞争、owner 拒绝后重开；同 intent 原回执一次效果；两个 expect-revision=1 的命令最终只一项更新；独立 SQL 计数 | 产品同时授权双 owner 不可达；补充测试通过实际排他和后继合法 owner 验 CAS，不绕过 flock 制造二写者。 |
| DB04 | PARTIAL / PARTIAL / LIVE_BLOCKED | 撤权先 COMMIT barrier、过期/epoch；新增 store SQL/OS 拒写；E-C01 预算/claim SIGKILL；真实 callback 丢失后业务原 receipt | 精确 after-pending-COMMIT/before-business-BEGIN 公开 pause seam 缺，无法穷尽业务 COMMIT 两侧撤权/取消；业务已提交与 agent admission 未结算的组合仍缺。网络 gate 不替代该业务调度窗口。 |
| FS01 | LOCAL_PASS / PARTIAL / 不适用 | E-FILES 新增真实 30MiB PDF/Document 正/超一；5×30MiB 实际聚合 seal 正/超一；ZIP metadata 10000/10001；坏路径/JSONL | 正向 10000 issued uploads 的实际 seal/import、150MiB ZIP 实际解压/不同内容及 API26 规模未测；规则/真实聚合边界已经补齐，不再一概列为上限未测。 |
| FS02 | LOCAL_PASS / PARTIAL / 不适用 | E-FILES 当前 copy/rename 十二故障窗口与真实 PaperCreate 两进程故障；单事务引用/receipt | API26 未逐点执行跨介质终止窗口；不得称 Android 全故障窗口通过。 |
| FS03 | LOCAL_PASS / DEVICE_PASS（源删除路径） / 不适用 | E-FILES pin/GC/deleting/损坏/缺文件；真实系统原 PDF 删除后新 Activity 选择原项目、打开私有副本通过 | 源 URI 授权主动撤销的设备负例仍未测；文件删除私有副本证明已经闭合，不再保留待定。 |
| AR01 | LOCAL_PASS / DEVICE_PASS（已测流） / 不适用 | ZIP32/Dart round-trip/descriptor/CRC/offset 本地负例；API26 DEFLATE host、坏 CRC 拒绝、真实 ZIP picker 导入通过 | 完整 archive corpus 每项在设备解压及规模资源测量未做；同输入多次成功不等于对全部边界无限推断。 |
| RC01 | BLOCKED_HOLD / BLOCKED_HOLD / 不适用 | E-I04 只读状态/哈希审计 | 原合同运行证据缺，明确 NOT_RUN；不在当前本地补测清单中重做该受限实验。 |
| RC02 | LOCAL_PASS / DEVICE_PASS（限定窗口） / 不适用 | E-RECOVERY 实际独立 SQL 观察 COMMIT→sender.close 丢 callback→unknown→kill Service→Supplier/Assistant 各查原 receipt，revision/history=1；Rust paper/agent SIGKILL | 本方法显式写真实 UI 同格式 journal、用独立真实 client 发 confirm，不冒称冻结主 looper 时点过原确认按钮；业务未 commit 窗口的 device kill/取消竞态仍不在该方法内。 |
| AN01 | PACKAGE_PASS / DEVICE_PASS（API26 ARM64） / 不适用 | E-PACKAGE、最终21 suite；8 次立即 close/rebind，同 PID 多 epoch，每次首个 health 不 retry；饱和 close/Unicode owner 释放 | x86_64 仅构建未实际运行；不存在该 ABI 运行宣称。真实设备峰值 IO 延迟与所有组件异常 teardown 未穷尽。 |
| AN02 | LOCAL_PASS / D01_TARGET_PASS / 不适用 | E-D01 原两 Settings→Send 方法、失败→修复 | 限定复用原实验目标，不推出新产品真实普通发送/搜索成功；新产品链由 AN07/CH02–04 单列。 |
| AN03 | LOCAL_PASS / DEVICE_PASS / 不适用 | 真实 UI CRUD/删恢复/分页；32 向量八字段 Service 重开；真实丢 callback UI 查回执只一效果 | 设备引用投影/新引用拒绝及删改竞争专门组合仍未完整覆盖，本地引用规则已有。 |
| AN04 | LOCAL_PASS / DEVICE_PASS（目录/ZIP 实际入口） / 不适用 | 实际系统目录与 ZIP picker 选择→源预览→可见确认→导入论文详情；平台 DEFLATE/坏 CRC 保护通过 | 测试包为小型 JSONL 语料，目录/ZIP 内多附件、物理全集比对和 import 在途 kill 后重启组合未全测。 |
| AN05 | LOCAL_PASS / DEVICE_PASS / 不适用 | 无项目可新建；真实系统 PDF 选择、预览取消不发布、重选填六字段、确认后论文可找并打开；删原 PDF 后新 Activity 打开私有附件通过 | 限定已测一页真实 Android PDF；未声称全部 PDF 格式、恶意 PDF 或大文档渲染保证。 |
| AN06 | LOCAL_PASS / PARTIAL / 不适用 | 预览返回/真实旋转零写、旧 lease callback 抑制、8-cycle owner 交接；COMMIT→callback 丢失→杀 Service→双 UI 原 receipt 恢复且一次效果 | 确认按钮真实双击、未 COMMIT 窗口旋转/kill、精确取消 COMMIT 竞态仍有限定缺口；丢 callback 的 UI 恢复已补齐。 |
| AN07 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | C01 owner/transport/本地工具/可见预览和后续请求实现与离线测试；价格证明缺失时设备边界方法 | 真实模型答案、真实搜索和 live 模型工具→业务读取/写建议→披露→后续请求未执行。不能称 C01 未实现，也不能称 live 完成。 |
| CH01 | LOCAL_PASS / DEVICE_PASS（构建/边界） / 不适用 | E-HEADER 102 旧协议离线检查；E-C01 修复后 transport/runtime；当前候选 rebuild/lint/package 与设备 suite | 不据离线结果断言历史 unknown 的确切原因；设备未做真实 provider 请求。 |
| CH02 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01 accepted/schema/usage/history、本地单次派发及同会话边界 | 生产 HostedCostVerifier 未绑定，真实普通发送/连续发送/accepted answer/usage 未执行。 |
| CH03 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | E-C01 现存 SearchProvider 解码、空/非空结算、错误保留 unknown 的 fixture | 生产 SearchPriceVerifier 未绑定，真实外部来源及 live 空结果/错误未执行。 |
| CH04 | LOCAL_PASS / PARTIAL / LIVE_BLOCKED | SQLite 累计预算/attempt/unknown 保留；Kotlin send-gate 两顺序；取消/重开/会话撤销；设备缺证明拒派发 | live 有效授权/价格证明及实际外发取消/恢复未验证；旧 unknown 账与 I04 不变。 |
| PK01 | PACKAGE_PASS / DEVICE_PASS（runtime 身份） / 不适用 | 最终双 ABI/生成桥/APK hash/16384 对齐；最终 manifest 与设备 runtime build identity 一致，21 方法聚合通过 | package/selector source 通过只覆盖本候选；不推断 x86_64 设备运行或任何 live 成功。 |
| PK02 | PACKAGE_PASS / DEVICE_PASS / 不适用 | 当前独立 product 包/business-v2；生产无 fixture fallback、缺 proof 拒派发；最终 APK/设备 source identity | 旧 schema-v1 unknown 数据保持，不声称历史数据迁移；后续候选需重新固定身份。 |
| OR01 | LOCAL_PASS / DEVICE_PASS（21方法内容门禁） / 不适用 | E-GATE 最终4/4 unit，亲跑持久 manifest suite gate 21/21 PASS；所有日志/selector/count/exit与SHA身份绑定 | 只证明固定 required inventory 全运行；inventory 的21方法不是36复合场景全覆盖。 |
| OR02 | PARTIAL / DEVICE_PASS（同候选聚合） / LIVE_BLOCKED + HOLD | 当前21 selector无遗漏/重复、source/APK/test APK/run/log hash全绑定；持久原始日志已封存 | RC01/I04及live价格证明/真实模型搜索工具环路仍HOLD；表中残余compound边界保持，不宣称整个计划完成。 |

## 当前设备方法清单（21，含 1 个 setup）

最终 suite manifest 已与当前候选源码枚举核对，以下 **21/21 方法通过**。核心组16，picker组按 setup→PDF→ZIP→目录→删除指定源PDF后私有重开顺序运行5；`generatePickerInputs` 只生成输入，**不是第五项业务验收行为**。详见 [SUITE.json](product-device/final/SUITE.json)。

| 测试类 | 方法 |
| --- | --- |
| ContractCodecProductTest | `malformedUtf16AndRawLimitCannotTurnIntoAValidReviewedPlan`；`actualKotlinToRustCodecPreservesPairsAndUsesTheSameNfcRule` |
| ContractVectorsProductTest | `sharedVectorsRejectWithoutPlansAndOneEightFieldReceiptSurvivesServiceReopen`（内含 32 向量） |
| ProductUnknownRecoveryTest | `committedWriteWithLostClientReplyRecoversOnlyOriginalReceiptInUi` |
| ProductRecoveryTest | `rapidCloseAndRebindWaitsForPriorOwnersWithoutKillingTheProcess`；`closingWithAllRequestSlotsBusyStillRevokesTheLiveBinderLease`；`actualServiceDeathChangesEpochAndOnlyOriginalReceiptRecovers` |
| ProductLifecycleTest | `backFromReviewThenRealRotationDiscardsUnconfirmedDraftWithoutWriting`；`closingLeaseBeforePrepareReplyCannotReportStaleSuccessOrPublishSupplier` |
| ProductChatBoundaryTest | `explicitConfigurationCannotTurnMissingPriceProofIntoOutboundAuthority` |
| SupplierProductTest | `visibleReviewCrudUsesActualReceipts`；`dismissingReviewKeepsDraftAndDoesNotWrite`；`elevenRealSuppliersAreReachableThroughNextPage` |
| ResearchProductTest | `projectVisibleReviewThenActualPdfHostAndDetail`；`deflatedZipUsesFrozenArchiveAndSealsActualImport`；`corruptStoredMemberCannotPublishSnapshotOrPaper` |
| SystemPickerProductTest | `generatePickerInputs`（setup）；`pdfSystemPickerManualReviewAndPrivateAttachment`；`zipSystemPickerReviewAndImport`；`directorySystemPickerReviewAndImport`；`reopenPrivatePdfAfterOriginalRemoved` |

## 剩余证据边界与可执行缺口

以下不是已确认实现错误。已补的 32 共享向量、真实 SQL 拒写/OS 写失败、owner 竞争后 intent/CAS、30MiB/150MiB 实际聚合边界、真实 callback 丢失及双 UI 原 receipt 恢复不再列为欠账。

1. **仍可安全补测的 UI 组合**：真实确认按钮双击；未 COMMIT 窗口旋转/kill；URI 授权撤销、设备跨项目拒绝、supplier 引用投影/拒绝及删改竞争。现有独立协议 client 丢 callback 测试是实际证明，不等于每个 UI 组合已跑。
2. **跨账组合**：业务已 commit 但 agent admission 尚未结算的组合恢复，仍需本地端到端 fixture；独立两账各自持久性和双 UI 查业务原 receipt 不自动证明这一组合。
3. **设备模型工具对话框**：披露、建议可见确认、切项目/会话撤销的真实 Android 组件组合仍主要依赖离线协调器/SQLite；可补无网络权限负例，不把它提升为 live 工具链。
4. **规模边界有分层限制**：最大合法 Unicode supplier 完整字段的十项分页组合、10000 个实际 issued uploads 封存/import、不同内容 150MiB、150MiB ZIP 实际解压、API26 峰值内存/时延未测。已有 host exact-limit 成功和拒绝证据应保留，不能反写成“所有资源上限未测”。
5. **当前公开接口不可精确触发的故障**：SQLITE_FULL 不等于已测 StorageIo；同一 SQLite 连接 max_page_count 未暴露，不能填共享盘。精确业务 COMMIT 两侧撤权/取消调度欠缺公共 pause seam；双合法同时 owner 在 flock 不变量下不可达。逐磁盘 flush/断电也未测。以上要明确 reachability，不能通过绕 owner、新增未批准生产 hook 或放宽断言制造通过。
6. **本轮已关闭的 picker 证据缺口**：固定候选 setup/PDF/ZIP/目录/删除指定原 PDF 后私有重开最终顺序链已经通过；PDF 草稿取消也在真实 picker 方法中实际零发布。它们不再是待办，剩余是第1/4项列明的权限负例与规模组合。

## 更新与停止条件

本核验轮次仅维护此文档，未运行 Gradle、adb、网络、凭据或付费调用，未改源码/测试或其他作者文件。最终同候选 suite/package、持久原始日志及每run身份绑定已读取，核验者重跑4项门禁unit与21方法聚合均PASS；保留先前失败和修复经过。21方法通过只关闭实际证明的设备断言，不能把复合场景全部或 I04/live 自动改为 PASS。真机、发布、历史 Flutter 数据迁移不在本次要求内。
