# 前片准备阶段历史报告（不代表当前状态）

# Documents D1/D2 准备片回报

状态：PREPARATION_ONLY，D1/D2 BLOCKED（未实施），D3 BLOCKED。2026-10-23。

最新补充：用户新授权后，官方 Rust 1.93.1 与103个锁定包缓存已就绪，既有基线49项及StoreEvidence12项通过，锁文件未变。详见 [TOOLCHAIN.md](TOOLCHAIN.md)。下方退出127/禁止安装/产品测试NOT_RUN为前片当时记录；本次仅更新既有Rust基线验证，新公共服务RED/GREEN仍NOT_RUN。

计划：`64900d4a6a46a9ef2919bcf922fb059413b1ce82`，`docs/superpowers/plans/2026-10-23-document-pipeline.md`；基线/源码 SHA：`fd26dcdabcdac996bc2881e8141cac2b519966fc`。独立分支 `task/public-v02-documents-20261023`，工作区 `/workspace/muyon-documents-v02`。环境初始旧 main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003` 未用作基线。

父任务最新确认：C1 尚未实现；`848ad8bd3797b14008ba5a44e60f0737bfdf56f1` 只有阻断报告，不能当接口依赖。官方工具链安装由父任务另行处理；本线不重复索批、不安装。编码前必须重新读取 develop 及父任务交付的最终 C1/C2 接口/fixture SHA。

## 已完成的独立准备

- 完整读固定 Documents 计划、总索引、设计；扫描未发现 AGENTS.md，核对当前交接与既有 StoreEvidence/Reader 边界。
- [源码与测试映射](PREPARATION.md)：原 metadata/text owner、UTF-8 精确输入、scope/撤权/历史场景、OCR 区域与 confidence 来源、embedding 模板/模型描述、旧 ResearchIndex 来源缺口，以及发给 Contracts 的具体依赖/模块登记要求。
- [工程 gate 阻断草案](../../implementation/public-services-document-engine-gate.md)：按 getter/command 标 contract_only/blocked/deferred；原 FD、许可、账户身份、资源释放等前置缺失保持 BLOCKED。此草案没有解除任何 gate。
- 没有修改产品源码、测试、公共 types、services/mod.rs、core/FFI lib.rs、Shell、Reader、数据库或依赖。没有启动引擎或真实模型，没有新 fixture。输入场景全为待实施的合成测试说明，不是测试结果。

## 实际验证与原始证据

平台：当前保存云端 Linux/Bash 工作区；Python3/java 可发现；cargo/rustc/kotlinc 不在当前 PATH。历史交接中的 `/tmp/evidence-rust` 等路径不在当前 /tmp，未恢复或下载工具。

| 项目 | 原始命令 | 结果 |
| --- | --- | --- |
| 原基线回归尝试 | `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test evidence_local --test document_storage --test documents` | 退出127：`cargo: command not found`；测试 NOT_RUN，无测试计数，不能算 RED |
| 既有 Kotlin runner 尝试 | `bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/run-offline.sh` | 退出2：`NOT_RUN: existing Kotlin compiler unavailable; no installation attempted.`；测试 NOT_RUN |
| D1 public_documents 结构/行为 RED、GREEN | 计划命令，未执行 | NOT_RUN：C1/C2 未提供、公共模块/测试未写，且缺 Cargo |
| D2 Rust public_pipeline / Kotlin IndexCompatibility | 计划命令，未执行 | NOT_RUN：同上；未复制公共 types |
| 产品全量/FFI/Android 编译、设备、模型、外部效果 | 未执行 | NOT_RUN |

原始日志留在仓库外（不提交）：

| 文件 | SHA256 |
| --- | --- |
| `/workspace/documents-v02-evidence/baseline-rust.log` | `a326558a932a2a67436a997ada30bbb04a637812287a7435cac205a7a51c6e71` |
| `/workspace/documents-v02-evidence/baseline-kotlin.log` | `0e44d74d1df1711d2355e0c710cc82fdfaa9f2846df4ef361298cd620e6ebb46` |

本准备片不记录任何软件 GREEN、测试通过率或实际引擎调用计数。Markdown 静态检查实际通过：3 文件、8 个链接解析、围栏/空白有效；`git diff --cached --check` 退出0。不以这些文档检查代替产品验证。原始文档检查日志 `/workspace/documents-v02-evidence/markdown-check.log` SHA256：`9f6341522ffab7bafcdc445cd0e75c25122a45c1c8becd423c0711203f140c58`。

## 精确阻断/拒绝记录

| action | target | reason | outcome / 已完成工作 |
| --- | --- | --- | --- |
| D1/D2 编码 | Documents 公共服务模块/测试 | C1/C2 最终接口与 fixture SHA 尚未交付；父任务明确不得猜类型 | PENDING_DEPENDENCY，未尝试实现；已完成源码/测试映射 |
| 原基线 Rust 回归 | 上述 cargo 命令 | 当前 PATH 无 cargo | NOT_RUN，启动命令退出127；没有下载/安装 |
| 既有 Kotlin 回归 | 上述 runner | 无现存 kotlinc | NOT_RUN，runner退出2；没有下载/安装 |
| 工具路径只读探测 `ls -la` | `/root/.cargo/bin` | 文件系统返回 Permission denied | DENIED，未取得目录内容、未重试、未提权或换路径绕过；不依赖该目录继续文档工作。这不是已收到的 auto-review 拒绝 |
| 生产 FD/引擎接线 | D3/Reader Core | 未收到原阻断解除完整 SHA/批准，D1/D2及工程决定未满足 | BLOCKED，未尝试接线/替代读取 |

## 执行账本与裁定

Pre-flight：D1 消费 C1 ResultRef/ScopeRef/Digest/Coverage/ServiceError，D2 消费 D1/C1/C2 原 IntentId；接口均未到，不能实施。Kotlin descriptor 依 Rust fixture 语义投影，不能先创建第二事实定义。

Ruling：先交独立源码/测试映射和 gate 阻断草案，不把它记作 D3 已执行完成 — 父任务授权缺依赖时继续独立准备，且原 gate 不得绕过 — 若误解会高估交付，故状态和产品未验范围逐项保留。

Ruling：计划/设计只从固定提交读取并用固定 SHA 链接，不将 docs 计划候选作为代码基线 — 用户要求最新 develop 与未审候选分离 — 代价是当前工作区没有计划文件的相对本地链接，阅读需 git show 或固定网页。

D1：未开始实现；D2：未开始实现；D3：仅前置阻断登记草案。无已完成产品任务。唯一 develop/main 合入者仍为 B；本线只正常提交/push 独立候选，不合入、不强推、不删分支、不部署。

## 独立审查

非作者 reviewer `documents_preparation_review` 只读对照固定计划、设计及基线源码，并补齐 REPORT 原始日志/摘要核对。Important 无；可作为 PREPARATION_ONLY 文档片交付。reviewer 独立运行暂存 diff 空白检查退出0，未运行产品测试；未编辑、安装、下载、提交或 push。父任务通报的 `848ad8bd…` 对象本地不可独立核验，报告仅保留为父任务确认，不声称本地验证。

Final: minor (deferred): PREPARATION 的“路径相对仓库根”描述下，部分 `documents/`、`evidence/`、`product/ml/` 使用前缀缩写，影响直接定位便利性；完整首项路径及源码文件名保留。无产品正确性或授权放行结论。

独审不是 B 的集成验收；本片没有解除任何工程 gate。

## F6.4 身份澄清补充

父任务转交外部审查核查结论后，已对照原源码注释、processing_key和source_id构造，补充PREPARATION中的处理身份说明：`processing-<64hex>`为75字节的确定性处理身份，可一对一适配typed ResultId并关联完整source/scope；不是业务IntentId/Receipt，不另建结果账本。C1实际ResultId编码/长度校验与fixture仍须等固定SHA核对，不因本结论预先实现。

本片仅更新准备文档，无产品源码/测试变化；不增加产品PASS或行为RED/GREEN。

F6.4准备补充已由非作者 `documents_preparation_review` 对照源码独审，Important/Minor均无；两份Markdown围栏/空白及 `git diff --check` 实际通过。未运行公共API产品测试。
