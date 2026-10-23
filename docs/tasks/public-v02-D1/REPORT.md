# D1 版本绑定文本读取 — Rust 候选交付

2026-10-23。状态：Rust 只读适配源码与离线测试已交付；公共模块登记 PENDING_OWNER，动态引擎调用计数断言未实现，完整公共端口/Android/生产接线未交付。D3 BLOCKED。前片记录保留在 [PREPARATION-REPORT.md](PREPARATION-REPORT.md)，工具来源见 [TOOLCHAIN.md](TOOLCHAIN.md)。本报告取代前片“C1未到/无法编码”的当前状态描述。

## 固定依赖、源码与范围

- 原 develop：`fd26dcdabcdac996bc2881e8141cac2b519966fc`；本次远端复核未变化。没有从 main 开产品基线。
- 父任务授权消费的 Contracts 候选：C1 `6e7f774b1559a0a9693eeb195ba13c9ded561993`，C2 `b626c18a5dff184519e59bb866e5ed37362ac84e`，C3源码 `bf264bc62f5d2d65fa7d50b27a26ffee3c0ba6d9`，含报告HEAD `4d49a580cb518d9b0b80c9df3df1ff564194a639`。在本独立分支正常merge固定候选，依赖合并提交 `d480dcf6bcf1733227991ee80dc95c04216cf265`；不代表B已审查/合入develop。
- D1测试/不可用桩RED：`2868ef112f4321bc716b279c1fc0e77f0d011c08`；D1 GREEN源码提交 `7d9c8581980740be22324f8cb2f3142cd87ec26d`。D1/D2最终组合固定源码为 `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e`；下述最终workspace结果对应此组合的相同源码文件，不将中间D2红桩提交算整包通过。
- 共享fixture实核：types.json `af0e6170bceb8e1a12e0686ab2855353d257f1ca885b06b3e6dfbad3d81b70f5`；commands.json `9f7618861e7fbc33c82e53d06c2acefb06e9fe3e40129eb172085cb48d104adc`；drafts.json `e1012c72cccea844a65a66e3b4a7ce3ae3a5257bba476f98ee9b4983cefd1460`。读取C1/C2/C3完整REPORT及固定源码；共享合同、fixture、登记与FFI无本线改动。

新增 `services/documents.rs`、`sources.rs` 与 `tests/public_documents.rs`。get_metadata委托BusinessStore::read_document；describe_processing仅投影原owner产生的Utf8Text+Available结果，result_id沿用75字节processing身份，保留完整DocumentRef；不转换IntentId/业务Receipt、不建结果账本。TextResult无正文缓存，Coverage明确以原始UTF-8字节计量，normalization为utf8-original-v1。ResourceHandle仅声明，不发FD。

read_blocks只接受非空、最多100条既有EvidenceRef（沿用既有literal hit上界）；逐条StoreEvidence::open，返回整批前任一失败即丢弃已收集结果，不宣称批次共享一个事务。resolve_anchor先核对ResultId/textDigest/normalization/source，再调用同一个原open，重验实际bytes、grant/head/scope/lease及清理结果。没有隐式process、替代host、裸路径、数据库读取旁路或历史自动跳转。source_locator只是历史绑定元数据，不授予权限或证明原文当前可用。

## 实际TDD、回归和未验范围

先 `source /workspace/documents-v02-tools/env.sh`（仅当前进程环境变量），从本工作区运行：

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_documents
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test evidence_local --test document_storage --test documents
cargo test --manifest-path crates/Cargo.toml --workspace --all-targets --offline --locked -- --test-threads=1
CARGO_TARGET_DIR=/workspace/documents-v02-tools/clippy-target cargo clippy --manifest-path crates/Cargo.toml -p muyon-core --all-targets --offline --locked -- -D warnings
```

结构RED：缺documents.rs，退出101，不算行为RED。首次桩测试fixture错误使用60秒grant（原owner最多30秒），5项在准备阶段InvalidAuthority失败，不算行为RED；改20秒后，真实行为RED为4 failed/1 passed，退出101，成功用例被明确unavailable拒绝。实现后首次4 passed/1 failed，因为测试损坏blob状态用了不存在的deleted枚举；纠正为原schema的deleting，不放宽读取拒绝断言，随后GREEN为5/5，退出0。

覆盖：`甲😀乙`原样10字节，[3,7)精确emoji；[4,7)、伪造range/ID/page、错ResultId/digest/normalization拒绝；跨项目同digest来源不可复用；head升级旧引用拒绝且历史元数据不重绑；撤权、过期、项目删除、原blob不可读拒绝；unsupported/failed结果不标全文，Inspect/ReadText不混权。

指定旧回归15+18+16=49项通过，退出0。另有一次误把 `--lib evidence::store::tests` 过滤词与集成目标放在同命令，日志保留但不以被过滤目标计通过；之后按上面的准确回归命令重跑49项。最终完整workspace为38个测试二进制629 passed/0 failed/0 ignored，包含D1 5项、D2 5项和既有跨target执行，不等于629个独立场景。最终core all-target严格Clippy退出0，rustfmt --check五个新增Rust文件退出0。第一次Clippy有D2测试useless_vec，已机械改array后重跑通过，未allow降门禁。

限制：测试include实际服务源码，复用真实BusinessStore/StoreEvidence与C1公共types，不复制或伪造host。此方式验证模块源码，不代表正式 `services::documents` 导出/FFI调用点存在。只有实际读取/授权行为通过，不宣称PDF/OCR/embedding/index引擎、Android或真实外部效果通过。getter测试只确认既有receipt未变，不能证明动态parse/ocr/embed/build调用次数；无隐式调用是源码审查结论，动态计数断言仍未实现，未填写“运行计数=0”。

## 独审、登记要求与裁定

非作者 `documents_preparation_review` 独立重跑D1 5/5和当时D2 4/4，确认原owner授权、UTF-8、source绑定、无历史回退/替代FD/缓存正文入口。D1无Important；D2一个逐输入descriptor Important已新增反例实际RED→GREEN修复，见D2报告。最终629项与修复测试由执行者重跑，未冒称已经独立复审新修复。

Final: minor (deferred): getter的动态parse/ocr/embed/build计数断言未实现，旧receipt相等不能替代；静态审查确无这些调用。此前路径缩写与前片历史时态的可读性Minor保留在历史报告中，不作产品通过依据。

Contracts需串行登记 `pub mod documents; pub mod sources; pub mod pipeline;` 到其独占services/mod.rs；当前core lib.rs已由Contracts登记services且旧evidence已导出。Documents未改services/mod.rs、core lib.rs、FFI lib.rs。登记后需在固定组合SHA复验正式公共路径，host/FFI生产接线仍后置。缺原Reader解除记录时不接FD。

Ruling：仅在集成测试中include本次实际模块源码，不越权登记 — 保持Contracts唯一owner — 代价是尚不能认定公共导出或生产集成完成。

Ruling：Utf8Text parametersDigest使用原contract::stable_digest对精确对象 `{"input_kind":"utf8_text"}` 的规范编码；不重写摘要器或新增共享类型 — 固定本适配的输入参数语义 — 若后续合同选择不同编码，须更新适配/fixture并重验，不能把不兼容产物混用。

Ruling：原计划要求动态调用计数，但原owner无计数hook且不得为本片改其策略/引擎；先交可独立审查的真实只读源码/授权测试 — 不引入测试专用生产旁路 — 代价是该计数验收仍未完成，D1不宣称全部验收已闭合。

原Reader FD gate、生产派发均未解除；唯一合入者仍为B。本分支只正常提交/push，不合main/develop、强推、删分支或部署。

## 仓库外证据

所有原始日志在 `/workspace/documents-v02-evidence/`，不提交。最终6个Rust源码/测试fixture文件的逐文件SHA256清单为 `d12-final-source-manifest.json`，清单本身SHA256 `b872f60ebe9854b57f733dad24907231b5789e635120476645f0e6cb6223adec`。

| 原始日志（仓库外） | SHA256 |
| --- | --- |
| contracts-consumed.log | `0565b7a0d5bb908bdfd84e26005778cdc3eb0e0c6c670f0e5427197b96ce4b6c` |
| d1-structural-red.log | `a91c3d7c818dd6610e0066d90eea0f0667d2f0418a6314c17d2026f07ac484d2` |
| d1-behavior-red.log | `986908921df140201241cef38dcee377d0f87f6e47de50997f4650dba3815efe` |
| d1-behavior-red-valid.log | `0fd8d39f3c5b36719837d664417945e2cfd2e275be1d0557f8f99072fc30ef83` |
| d1-green-first.log | `b385ce795c171bd5398c1729ef9d02e8cf04f9b2d115baa373183aa05108b257` |
| d1-green.log | `a14da22b0795594c48889f6a64a7d778c1fe1b42b1b198111d0ebf605a07e15d` |
| d1-regression-filtered.log | `3e5e7b263e346438d73b166745c821d5cb1439314e1e0fc66d340c137da2ec9f` |
| d1-regression.log | `6bc80916a0e97c3180c9a0dd4730a86d3ae17906419634cb8bfe4a896b8f5f2a` |
| d12-final-focused.log | `4913cb21ee904803befb8884a3c2ac3eeef6fa6786b67098ba3b86a02225e398` |
| documents-workspace.log | `87738a43ce05746e0ef29fbf85aca482f092008ad9cdcc3c3a86344f0dea7630` |
| documents-workspace-final.log | `2594c53dd8ddfce822cd028ebeb3b27f5f9069a40b3e5cc7e42fe9ccd840788e` |
| documents-clippy.log | `a3ff5b8d4dc757944c4f57219c52816efe7e1bc922786c833cdc508d0a446189` |
| documents-clippy-final.log | `7f60a216ccee29255aea0751ffab87ce106948cdfa95102fbed33d637d89e759` |

固定最终源码HEAD `4bb47be7b3b34ff66da3b2e9bf740e924f56bd1e` 后又重跑focused命令D1/D2各5项通过，日志 `d12-fixed-4bb47be7-focused.log` SHA256：`73c2c1535b2b0deae27a18c38af5f3af627624a518b2ff47992d535888849b7e`。

## 最终证据文档审查

非作者 `documents_preparation_review` 另只读审查本轮报告与gate，独立核对27处日志摘要、6文件固定源码manifest、完整workspace/focused计数、官方质量组件校验及Contracts独占文件无本线变更，未发现实质错误/新增Important。此次是报告与证据审查，不是修复代码复审或重跑全套。执行者另运行当前三份报告/gate检查：19个表内日志SHA匹配、全部提交ID可解析、源码manifest未变、629次计数一致；日志 `d12-report-check.log` SHA256 `f95d92adc88b69948b0d47dfe5231eb304fa01687c09da2c0bf1caccebb7d2e4`。

Final: minor (deferred): TOOLCHAIN.md开头还保留工具准备阶段的“D1/D2未实施/C1/C2未到”；gate中getDescriptor行还保留“等D2 fixture”措辞。当前已有Rust合成fixture，生产descriptor仍未接线；本主报告/D2报告明确当前状态，旧文字不作为验收依据。
