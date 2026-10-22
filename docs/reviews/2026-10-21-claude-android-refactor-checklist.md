# 给 Claude：Muyon Android 整体改造审查清单

请对本分支做独立、端到端审查，检查实现是否符合用户目标、是否存在可复现缺陷，以及已有证据是否支持交付结论。不要只审最新一次提交，也不要把这份清单或历史 PASS 当作审查结论。默认只读；发现问题先报告，不修改源码、削弱测试或覆盖原始证据。

## 1. 审查对象与固定版本

- 仓库：`https://github.com/mightyoung/Muyon`。
- 分支：`codex/muyon-android-refactor`。
- 本轮代码和证据截止提交：`e7dfe699`。本清单随后提交；审查时先记录远端完整 SHA 和本地 dirty 状态。
- 最终安装包源码：`79dca05ba6ff84dbc8a60d0838951aec6720227a`；后续证据/清单提交没有重新构建 APK，不能把文档 HEAD 冒称 APK 源码。
- 本轮重点差异：`cebc6876c31651d5037dc54a10dfd1c72129dca0..e7dfe699`，涵盖搜索修复、原生业务工作台、界面、模型和 agent workflow。该基线是本轮修复前的检查点，不等同于 `develop`。
- 全量集成差异还须检查：`origin/develop...HEAD`。推送前远端 `develop` 为 `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`；改造分支继承了此前大量未合并工作。报告应区分本轮新增问题和继承问题，不能只选重点范围就宣布全分支通过。
- 原始工作区 `develop` 的两处 macOS xcconfig 本地修改不属于本分支交付，不应重置或顺手提交。

建议先运行：

```sh
git fetch origin
git status --short --branch
git rev-parse HEAD origin/develop origin/codex/muyon-android-refactor
git merge-base origin/develop HEAD
git diff --stat origin/develop...HEAD
git diff --stat cebc6876c31651d5037dc54a10dfd1c72129dca0..e7dfe699
```

若远端已变化，请记录新的 SHA 并按实际差异审查，不重置其他人的工作。

## 2. 用户目标与需求完整性

- [ ] 对照总计划和任务分解逐项建立“需求→实现→测试→缺口”映射，区分已实现、部分实现、未实现、证据不足和外部阻塞。
- [ ] 科研工作台支持真实论文添加、手动 PDF 元数据、私有附件，以及 ZIP/目录导入；供应商业务具备真实 CRUD、删除/恢复与持久身份。
- [ ] 布局参考 WorkBuddy；最新视觉要求以 Muse 的组件、交互、配色、按钮和圆角为主；文字排布/字体参考 Claude。早期 Grokbot 组织参考不能覆盖用户后来的简洁要求。
- [ ] 单 agent、群组、会话切换和管理行为可用；群组成员展示不能被误当作已经具备多 agent 自动协作。
- [ ] 对话默认不堆积配置和操作按钮；费用、原始参数、技能管理和技术记录按需展开，失败/未知结果仍清楚可见。
- [ ] ChatGPT/Codex 风格的子任务生命周期、隔离、工具和 skill 管理在后端真实执行；明确区分本地工具任务、手动创建 AI 子任务与尚未验收的模型自动派生。
- [ ] Claude 风格的过程展示只使用真实请求、工具和公开事件；检查是否伪造了模型思考、完成状态或回复。
- [ ] embedding 和 OCR 是真实离线模型推理及业务集成，不能以占位向量、样例 OCR 文本或仅静态打包代替。

入口文档：

- `docs/tasks/muyon-android-refactor/planning/muyon-android-refactor-20261020.md`
- 同目录 `muyon-android-refactor-tasks-20261020.md`、`muyon-android-refactor-tests-20261020.md`
- `docs/tasks/muyon-android-refactor/ACCEPTANCE-MATRIX.md`、`SOURCE-MAP.md`、`PROGRESS.md`
- `docs/implementation/agent-workflow-and-conversation-20261021.md`

历史计划/进度有各自的旧候选版本和早期范围。最新用户补充、模型报告和 workflow 报告应一并对照；发现记录过时或冲突也应列为审查问题。

## 3. Rust 业务、数据和授权

重点：`crates/muyon-core/src/`、`crates/muyon-core/tests/`、`crates/muyon-android-ffi/`，以及实际复用的 `experiments/redesign/` 服务/合同实现。

- [ ] 手动 UI 和模型工具共享业务用例与授权边界；FFI/Service 不另造一套可绕过的业务写入路径。
- [ ] workspace/project/session/epoch/generation、原 admission/intent、参数和 revision 全链绑定；不信任模型、UI JSON 或陈旧回调提供的权限。
- [ ] schema2 严格字段、Unicode、超大 revision、未知字段/畸形输入、分页边界和错误净化符合合同。
- [ ] 业务变化、history、intent、原回执的事务与 CAS 正确；重复点击、丢回包、重连和重启不产生重复写入。
- [ ] 取消、撤权、提交及结算的线性化点清楚；提交后不能因为取消而抹掉业务事实，结算成功也不代表业务已提交。
- [ ] SQLite 排他 owner、Service predecessor drain、恢复与并发队列不存在双 owner、死锁或陈旧执行。
- [ ] unknown/pending 保留原身份，只查不重发；没有因为超时、切换会话、清理或展示逻辑释放未知费用保留。

## 4. 附件、导入与恢复

重点：Rust 附件/导入端口，以及 Android `research/ResearchFileHost.kt`、`LocalResearch.kt`、`ResearchScreen.kt`。

- [ ] 文件发布与 DB 不假装具备跨介质原子性；复制前持久化意图，staging/pin/digest/rename/引用发布/恢复顺序正确。
- [ ] 同内容对象复用前验证哈希和长度；不覆盖已存在的 blob；reader/publisher pin 与 GC 互斥正确。
- [ ] 来源 URI 删除/失效后私有附件仍可重新打开；异常和取消零误发布，残留可解释且可恢复。
- [ ] ZIP 路径、重复条目、大小/CRC/长度、压缩膨胀、目录遍历和符号链接边界有效；导入快照不可变。
- [ ] 文件、数据库满、进程终止、lost callback 的测试各自证明什么写清楚；模拟错误不冒充真实 SQLITE_FULL 或断电验证。

## 5. Agent、工具、skill 与外发控制

重点：`agent/workflow.rs`、`agent/owner.rs`、`agent/tools.rs`、bundled `skills/*/SKILL.md`；Android `ProductService.kt`、`ProductChatRuntime.kt`、`ProductSendGate.kt`、`ProductHttpsTransport.kt`。

- [ ] 根/子任务持久身份、层级、两个活跃/八个总子任务限制以及取消传播可信；取消后的迟到结果不改变已停止事实。
- [ ] 子任务使用独立会话和显式输入；不会静默继承整段父历史、私有记录或其他项目权限。
- [ ] skill 先元数据后正文，digest 可追溯；停用后创建/执行被拒绝；正文不能授予新工具或数据访问权。
- [ ] 子任务工具目录限制贯穿准备、模型返回、工具确认和 followup；越权 tool call 拒绝且保留未知保留额。
- [ ] 原始 request ID 与完整 followup chain 始终关联，snapshot/cancel 能覆盖尚未观察过的 followup。
- [ ] 在新 root、其他子任务、普通聊天路径均不能绕过当前 scope 的 unresolved 请求；累计预算不是每个子任务重置。
- [ ] 外发预览显示实际发送字段、费用和来源，确认绑定原请求；业务读/写、搜索与模型请求权限不混淆。
- [ ] restart 不重播队列；旧 session 只能按既定边界读取，不能重新取得旧任务的可变控制权。
- [ ] polling 不制造重复事件，seq 稳定；result/快照/任务输入/请求链均有大小或数量上限。
- [ ] 当前生产价格 verifier 为 None 的路径确实受阻；展示 blocked 不冒充等待确认或成功。禁止为了“跑通”替换价格证明或制造授权。

## 6. OCR、embedding 与检索

重点：Android `ml/LocalModels.kt`、`LocalEmbedding.kt`、`LocalOcr.kt`、`OcrGeometry.kt`、`ResearchIndex.kt`、`research/LocalResearchPanel.kt`，以及 `ml-native/`、构建脚本和模型清单。

- [ ] 模型真实加载、推理、输入归一化、tokenization、向量维度/归一化、OCR 检测/裁剪/识别/阅读顺序正确；失败清楚可见。
- [ ] 论文文本、索引、附件与项目绑定；删除、更新、换项目、重建索引和 app 重开不会泄露旧记录或产生幽灵结果。
- [ ] 后台线程、取消、JNI 生命周期、内存峰值和资源释放合理；无 UI 线程长阻塞，无隐式模型联网下载。
- [ ] 模型文件、字典、hash、原生 ABI 和 APK assets 一致；字体、模型、ONNX/llama/PaddleOCR 来源及许可证可分发。
- [ ] 真实推理证据、检索行为证据与静态打包证据分开，不将 API26 4KiB 内核验证扩大成 x86/16KiB 内核或真机通过。

## 7. Android 交互与视觉

重点：`MainActivity.kt`、`design/Workbench.kt`、`agents/AgentCatalog.kt`、`AgentLibraryScreen.kt`、`chat/ChatScreen.kt`、`AgentWorkflowSurface.kt`、`ChatPresentation.kt`、`ConversationRichText.kt`。

- [ ] 至少实际检查紧凑手机、200% 字体、宽屏/深色、键盘展开、旋转和返回；记录实际运行过的组合，不能用静态代码检查代替视觉验收。
- [ ] 输入框和发送按钮不被 IME/system inset 覆盖；关闭抽屉的不可见控件不留在可访问性树中。
- [ ] 长中英文、空结果、错误、unknown、长任务名、多任务和长记录列表不溢出、不截断关键状态；折叠状态可理解。
- [ ] 单 agent、群组和项目切换不会混会话、原请求或业务回执；异步 callback 不把旧会话结果灌入新页面。
- [ ] 代码复制精确、表格可滚动、文字可选择；Markdown 嵌套/未闭合标记有界，危险链接和 HTML 不执行。
- [ ] UI 不只“看起来像”，还需检查对比度、字体 fallback、触达尺寸、TalkBack 标签及功能发现性；参考素材不可用时明确标记比较证据不足。

## 8. 独立验证与证据核对

- 最新候选：`docs/implementation/agent-workflow-proof-20261021/README.md`，以及 `candidate.json`、`suite-manifest.json`、`suite-gate.json`、`installed-identity.json`、原始日志和 `screens/`。
- 模型集成：`docs/implementation/android-local-models-20261021/README.md`。
- Muse 界面：`docs/design/android-reference-20261021/muse-final/README.md`。
- 业务基础验收：`docs/tasks/muyon-android-refactor/product-device/final/README.md`。

- [ ] 独立核验源码 SHA/build ID、crates tree、generated bridge、APK/test APK 哈希和设备已安装哈希，不混用不同候选的测试结果。
- [ ] 最新记录为143次 Rust 测试执行/16 suites、54/54设备方法、4个 Python gate 测试；核对实际测试目录和日志，而不是只核对数字。执行次数不能自动当作唯一场景数。
- [ ] Clippy 的 warnings-denied 和 Android lint 分开：后者0错误、33 warnings、6 hints；逐项判断警告是否影响交付。
- [ ] Device gate 拒绝失败、跳过、遗漏、重复 selector、混构建以及仅 adb exit0。检查测试是否过度镜像实现、缺少并发/失败断言或偷偷放宽。
- [ ] 54方法包含49个非 picker 和5个有序 picker；生成 fixture、PDF、ZIP、目录、移除原 PDF 后私有重开按依赖顺序执行，不清 app 数据制造“成功”。
- [ ] 保留并理解 `diagnostics/` 中两轮失败：`error:null` 被误判和 fixture 分页上限；确认修复的是实际根因，未隐藏反例。
- [ ] 可用环境下独立运行针对性 Rust/Android/gate 检查；不能运行时记为未复验，不能把已有日志写成“本次实测”。本地临时 APK/SDK/模型/cache 路径不是远端可用资源，缺失应明确报告。

## 9. 保持现有禁止与未验收边界

I04（历史 legacy→HTTP→重开实验）已有明确拒绝，不能重试、换工具、改包装或使用等价路径。不要读取/导出 provider 密钥、发起付费模型/搜索调用、重发 unknown、删除未知保留额或清空用户数据。独立构建和只读/本地 fixture 验证不代表获得这些权限。

整体36场景仍为 PARTIAL/HOLD。自动模型派生、远程并行 AI/父任务综合、真实 provider/tool-loop、公开思考摘要接入、生产价格证明、真机/x86运行/16KiB内核和发布分发尚未由本轮证明。请审查这些缺口是否妨碍合并/交付，并明确需要什么证据；不要把它们伪装成完成，也不要擅自执行已禁止的实验。

## 10. 请输出的审查报告

建议保存为 `docs/reviews/2026-10-21-claude-android-refactor-report.md`：

1. 审查分支/完整 SHA、实际范围、运行环境、执行命令与退出码；未检查的范围单列。
2. 按 P0/P1/P2/P3 排序的问题，每条给出文件:行号、触发条件、用户影响、复现/反证、最小修复建议及所需回归。
3. 需求覆盖表：实现状态、证据、未完成内容、阻塞是否可恢复。区分确定 bug、设计风险、需求缺口和验证不足。
4. 对 UI、业务/数据、权限/外发、模型、恢复/并发分别给出判断；优先报告跨层问题，不只做风格点评。
5. 给出 `APPROVE / REQUEST CHANGES / INSUFFICIENT EVIDENCE`，并分开说明“允许合并该分支”和“整体产品/发布验收”。没有问题也需说明验证边界。

请直接开始审查，不需要先征询是否继续。若需要修复，先交付审查结果；本清单授权的是审查，不是合并、发布、收费实验或删除数据。
