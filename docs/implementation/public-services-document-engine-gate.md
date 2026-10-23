# 公共资料管线工程 gate — 阻断登记草案

状态：BLOCKED。本文是 D1/D2 依赖到达前的独立准备，不是 D3 完成、批准申请或生产接线授权。固定计划 `64900d4a6a46a9ef2919bcf922fb059413b1ce82`；静态源码基线 `fd26dcdabcdac996bc2881e8141cac2b519966fc`。D1/D2 尚未实施；Reader Core 原安全阻断没有收到解除 SHA/批准记录。

Documents 只复用既有合法 StoreEvidence 文本 owner，不实现替代 FD 桥、URI/路径读取、引擎启动或外部资料接入。真实模型、付费实验、真实 Connector、凭据配置、第三方程序下载/执行及新依赖禁止。

## 状态定义和逐端口清单

present 表示源码已有特定内部能力，绝不表示公共端口已接通；contract_only 表示只有固定计划中的候选合同；blocked 表示缺强制前置不得生产接线；deferred 表示后续单独确定。本表按方法逐项登记，公共方法目前没有 present 项。

| 阶段 | 公共 getter / command | 状态 | 既有事实与欠缺 |
| --- | --- | --- | --- |
| 1 Document | getMetadata | contract_only | 内部 BusinessStore::read_document present；公共错误/scope 适配等 C1/C2/D1 |
| 1 Document | listVersions | deferred | D1 不提供完整公开版本枚举与历史授权 |
| 1 Document | readBlocks | contract_only | 原 StoreEvidence::open present；D1 只开放原 find_literal 命中的已绑定引用，不等于任意范围/全文分页 |
| 1 Document | resolveAnchor | contract_only | 原 open present；精确 ResultId/textDigest/normalization 校验等 D1 |
| 1 Document | openReadHandle | blocked | ResourceHandle 仅候选；不签发 FD，等原 Reader Core 解除及宿主 lease/release |
| 2 Document | importDocument | blocked | 原 owner/Operation/幂等回执映射未交接；不另建入口 |
| 2 Document | createVersion | blocked | 精确版本、授权、候选/确认发布路径须原 owner 支持 |
| 2 Document | requestParse | blocked | process 有真实效果；公共命令及任务/回执映射未固定 |
| 3 OCR | getResult | contract_only | OcrLine 有 text/points/confidence；缺结果注册与来源封套，不调用引擎 |
| 3 OCR | getCoverage | contract_only | 未有公共失败单元/部分覆盖投影；未知总量不算百分比 |
| 3 OCR | requestOcr | blocked | 原 FD 解除、引擎许可与任务命令前置不满足 |
| 4 Embedding | getDescriptor | contract_only | 768 不足证明 model/tokenizer/chunk 兼容；等 D2 fixture |
| 4 Embedding | getCoverage | contract_only | 精确输入文本 ResultRef 和覆盖定义未接线 |
| 4 Embedding | requestEmbedding | blocked | 本地模型构造即执行 nativeOpen，getter 禁止触发；公共命令未接 |
| 5 Index | getCoverage | contract_only | 旧 contains 不等于公共覆盖/新鲜度；snapshot/inputs 未接线 |
| 5 Index | search | contract_only | 内部 ResearchIndex::search present；旧 paper-only 来源不足，D2 仅纯兼容校验 |
| 5 Index | resolveHit | blocked | 需公共来源图与每次 scope 重验，不静默跳到当前文档 |
| 5 Index | requestBuild | blocked | 构建命令/配额/产物注册/幂等 owner 未固定 |
| 5 Index | requestRefresh | blocked | 刷新与查询分开；不以查询隐式启动 |
| 横向 Task | getTask | contract_only | D2 只读 JobSnapshot，不另建账本 |
| 横向 Task | subscribeProgress | deferred | scope/游标/容量/释放生产策略未定 |
| 横向 Task | requestCancel | blocked | 仅可信映射可到原 C2 cancel_original；wire JobId/IntentId 不能授予取消权 |

## gate 的失败条件与待固定证据

任一必需证据缺失即 BLOCKED；这些是文档审查拒绝条件，当前没有软件行为 RED。

| 前置 | 当前证据 | 解除所需 |
| --- | --- | --- |
| D1/D2 与 C1/C2 固定合同/fixture | 未收到父任务交付 SHA；无产品实现 | 完整源/fixture SHA、独审、实际 RED/GREEN 与回归 |
| 原 Reader Core FD 安全解除 | 未收到，保持原阻断 | 原任务完整通过 SHA、批准记录、准确覆盖与剩余限制；不能用本文件解除 |
| 引擎固定版本/模型摘要 | 仅静态观察源码引用 | 原 owner 给可审版本、模型与 tokenizer/config 摘要和输入输出签名 |
| 许可证/NOTICE/分发条件 | NOT_VERIFIED | 固定版本许可、NOTICE、模型与字典许可分别核验；不能仅凭库依赖存在推断 |
| Android minSdk/ABI | build.gradle.kts 静态 minSdk=26；arm64-v8a/x86_64；ONNX runtime声明1.23.0 | 固定构建源/产物 SHA 与逐 ABI 验证；静态配置不证明 engine 可运行 |
| 账户/scope/grant 真源 | 旧 DocumentRef 只有 workspace/project | 可信宿主绑定，跨账户/跨项目策略与实际撤权/过期测试 |
| 任务/原回执 owner | 未固定公共映射 | 原意图、任务尝试、取消、unknown 对账与重试 owner；禁止新增执行账本 |
| 临时资源表/释放 | 未决定 | purpose、精确版本、scope、expiry、lease、release、并发与异常时序 |
| UI Shell/内核所有权交接 | 原 Shell 仍在设置/菜单收尾 | 原 owner 明确接线文件和可改范围；Contracts 独占登记/FFI |

## 生产资源决定必须填写的字段

以下全部 UNDECIDED，不填猜测值：每 scope 并发任务数/队列容量/预算、最大结果字节、每阶段页/块限制、缓存配额/淘汰与失效条件、订阅容量、游标有效期与恢复、慢消费者、关闭/取消/释放先后、进程死亡/资源过期与重新快照策略。既有 MAX_BYTES=2MB、ResearchIndex 限制或 C3 合成测试容量均不能替代生产选择。

结果图需要明确：不可变 DocumentRef → parse/OCR ResultRef → 文字/分块 ResultRef → EmbeddingResult descriptor → IndexSnapshotRef 的精确输入集合 → hit → SourceLocator。旧作业完成只能保留历史产物，修改当前指针必须检查原 expected revision 与 scopeGeneration。源文件删除或 grant 失效返回明确不可用，不以缓存或索引代替原文。

OCR 图像 SourceLocator 须单独评审坐标系、单位、页索引、旋转/裁切、原图版本及 confidence 算法/引擎来源；不丢区域/置信来源，也不以 confidence 表示主张可信。Office 须逐格式逐操作列 supported/read_only/unsupported/needs_license/needs_network/unknown，并区分批注保存、编辑候选、确认发布、导出及原回执。现有 narrow edit 不升格完整 Office 支持。

## 后续执行顺序

1. 先完成 D1/D2 的离线合同及独审；每段更新上述证据，仍不解除 FD gate。
2. Document 五个 getter 独立评审，再评审 import/createVersion/requestParse；各段给精确实施签名、原 owner 同意与测试方案。
3. 依次评审 OCR、embedding、index；每段独立分支、行为 RED/GREEN、回归与独审。无原 owner 支持的 command 返回 capability_unavailable；失败 getter 仍不启动工作。
4. 全部前置固定、详细接线计划经用户审阅后，才另行申请生产实施。真模型/外连/许可费用仍单独授权。

正常回退只 revert 新适配，保留历史结果、原 IntentId/Receipt 和 unknown 状态；不删记录、不降 schema、不重放命令。唯一合入者为 B；本候选不合 main/develop、不部署。
