# 正式本地 Bot 定义创建接口：固定组合源

> 后续Important修复与当前依赖以 [CREATION-TAIL-FIX.md](CREATION-TAIL-FIX.md) 为准；本页15c/8项结果保留为历史，不作为当前组合放行。

2026-10-22 UTC。本批在已批准 U06/U11 方向内，从编辑归档推进到真实本地定义事务；仍无模型、搜索、账户、凭据或执行授权。

## 现源码复用与所有权

- 开工基线：`53b9b597e190db6b6619a18e8746f2985f488fbc`。重新核实原Android候选仍为 `f4781e16ddf4e542b983fbd77f266a0071148255`。
- 完整总纲此前已读；U06区分编辑/保存/提交，U11要求创建前复核且创建不启动模型。Grok名称推荐控制流仍未证，本实现为独立设计。
- Kotlin `AgentProfile` 已有id/name/role/instructions字段，`AgentCatalog` 是SharedPreferences目录；其保存不能参加BusinessStore SQLite事务，Rust此前无正式Bot定义表。因此在**现有BusinessStore连接/数据库**新增定义及原intent表，不另建数据库/磁盘store，不把草稿当Bot。字段语义复用name/role/purpose→instructions；B接UI时应投影新定义，不能再对AgentCatalog双写或自动导入历史目录。
- 依赖草稿owner固定 `15c65c7c9c1f0af1e73c8092b2de2ac78939eea7` 的 `bot_drafts.rs`：复用DraftBinding、正式read校验和同DB草稿记录，不修改该文件。草稿namespace/generation/storedRevision仍由其唯一owner维护。
- 唯一生产写入文件：新增 `crates/muyon-core/src/bot_definitions.rs`；自身测试为 `src/bot_definitions/tests.rs`。不改bot_drafts/documents/FFI/lib.rs/Runtime/Service/UI/main/develop。`lib.rs`真实导出由B组合。

## 小计划落实

1. 测试先行：`6d2bc5e862a780c728b5a0b03bac2767549f7204`。缺模块时编译RED，保留原诊断。
2. 正式定义及事务原intent：`4ad50b82ed46a8736e23a3d5ad8876c0ab96f363`。
3. 非作者提出的四项证据缺口补测：`bdc58460410b4c5b51c52e10516f058a0079092e`；生产模块与4ad逐字相同。
4. 最终交付只追加本报告、原始日志和命令/哈希，不自行合入。

## Host API与状态

所有入口只供可信宿主调用，不挂给模型工具分发器：

- `prepare_create(store, conversation, project, &DraftBinding, intent_id) -> CreateReview`：从当前已保存草稿解码name/purpose/role；必须完整合法。保存原intent与精确配置摘要、namespace/draft/generation/revision/archiveDigest、workspace/conversation/project、ownerEpoch。只产生prepared审查，不创建定义。返回明确的定义预览、摘要和原intent。
- `confirm_create_trusted(store, conversation, project, intent_id, review_digest) -> CreateReceipt`：宿主展示同一审查并取得明确确认后调用。先复核scope/CAS/archive及epoch，独立提交durable pending，再在同一事务写Bot定义+committed原回执。
- `lookup_create(...)`：只查询同scope原intent；pending/unknown返回Unknown，无重发。已提交时校验原回执与真实定义一致；丢失回包后查询同一Bot ID。
- `cancel_prepared(...)`：仅prepared可以明确拒绝；pending/unknown/committed不能取消解锁。显式拒绝后允许新intent重新复核。
- `recover_previous_owner(store)`：旧owner prepared封为rejected，旧pending变unknown；绝不执行旧意图。宿主每次打开需要新epoch。旧prepared在恢复前直接确认也被epoch检查拒绝。
- `get/list(store, conversation, project, ...)`：按当前workspace/conversation/project读真实定义。list首次显式访问会初始化本功能表，不能宣称为零写入的探针。菜单聚合/主Bot/置顶归属由B另接。

状态：prepared → 明确确认 → pending → committed；中断/存储无法证明结果则查原intent并保留pending/unknown。明确拒绝prepared可建立新审查；unknown没有重建或“换intent试试”接口。stale确认保持原prepared，需用户显式cancel后重新复核，不自动接受新配置。

`BotDefinition`只有稳定id/name/purpose/role、`runnable=false`、`unavailable_reason=provider_not_configured`。无model绑定、provider账号、密钥、执行grant、预算或权限。技能/资料选择不伪装成可执行授权：本批只创建当前已持久化的三项编辑配置及其宿主作用域，未声明完整技能配置创建已接线。

Bot ID是namespace/draft/generation结构化身份的SHA256派生，与名称和intent分离。同名不串ID；同草稿另intent在原prepared/pending/unknown/committed存在时拒绝；定义表draft_key也有UNIQUE。回执不是模型可运行证明，定义成功不会调用/启动模型。

## 数据安全与原子边界

三表仅在原BusinessStore连接创建：`local_bot_definition_meta`、`local_bot_definition_intents`、`local_bot_definitions`。精确DDL/schema/workspace校验，部分或未知schema拒绝；不迁移历史库。最大4096原intent；继承本地草稿128个登记边界，list拒绝超出128条异常集合。

prepare先复用草稿模块完整schema/binding读取；随后持有BEGIN IMMEDIATE重新读取并绑定实际storedRevision/归档bytes/digest。confirm在pending之前和effect事务中均重新CAS；归档的严格UTF8/长度/字段锁/模板出处重新校验。定义只接受完成的名称、用途和角色，字段缺失不是默认创建许可。

pending先耐久提交；定义与原回执共用第二个SQLite事务。任何effect/receipt/commit存储错误均提示query-original；不能当作确定失败重新建。SQL失败后pending仍冻结，旧归档恢复/正常保存新archive都不能清除创建表中的原intent guard。不存在从未知归档反射修改reducer的路径。

校验和和配置hash不认证恶意重写的整库；本功能不对攻击者控制整个app-private数据库的任意改写/回滚提供防护。宿主负责私有数据库归属、唯一owner、新epoch、明确用户确认和当前scope，不能把UI传来的“confirmed”布尔当可信授权。没有暴露公开FFI JSON入口或第二套执行grant系统。

## 验证与独审

复现：`python3 docs/tasks/bot-setup-draft-20261022/run-creation-checks.py`。

脚本克隆到/tmp临时组合副本，抽取上述固定依赖bot_drafts.rs，只在副本lib.rs追加两模块导出；原工作树公共文件不变。用Rust1.99.0和系统真实SQLite运行合成数据测试。环境原无Rust，公开工具链只装/tmp；首次完整测试因系统缺`libsqlite3.so`开发链接名而链接失败，原失败完整保留。仅在/tmp提供现有系统libsqlite3.so.0的链接别名，不扩权限或更换SQLite实现。依赖lab有既有read/write C ABI lint警告，保留stderr，不宣称零警告。

作者和非作者最终均 **8 passed/0 failed/0 ignored**：

1. 确认前无定义；同原intent重复确认/lookup同回执，定义数1，business_grants数0。
2. 正常draft.save真实CAS推进版本后旧确认拒绝；错误摘要/跨conversation拒绝。
3. effect失败后重开unknown；正常保存新archive及重放旧archive均不能新intent解锁。
4. committed原定义/回执跨连接关闭和重开保持一致，无再次执行。
5. 旧owner prepared不能确认，恢复封存后显式新review；cancel后不能提交。
6. 归档破坏、功能schema版本改为2时拒绝。
7. 自建合成子进程：另一只读SQLite连接观察durable pending，再杀该子进程；新owner重开unknown且零定义。**只证明该pending边界，不声称已精确进入trigger语句，也不涉及历史I04或任何设备。**
8. effect INSERT之后receipt UPDATE触发失败，独立只读SQLite看到零定义；移除触发器也不重放原pending。

非作者最终固定bdc5846，UTC06:22:09.231679–06:22:14.852892，exit0；四项前轮证据缺口均闭合，无剩余阻断/应改。metadata SHA256：`8e48370b0eab52aeec5d26da5aca106b0004efe5c441a93a5d18f1b7801ad8e0`。

作者另在临时组合副本逐项去掉摘要校验、双阶段草稿CAS、原draft active-intent guard、旧owner拒绝，以及故意拆开定义/回执事务：五项均编译成功后被行为测试检出。规则、源hash、UTC、完整命令、exit及原始输出见 `creation-evidence/author-final/metadata.json`。旧6/7项中间通过与首次链接失败保留，不能替代最终8项结果。

全部日志、环境/版本/hash与清单在 `creation-evidence/`；从该目录运行 `sha256sum -c SHA256SUMS`。原始编译RED是API缺失，不冒称运行时断言失败。

## 剩余接线与HOLD

交付为实际可测的定义/回执事务模块，尚未由B导出到正式lib.rs/FFI或接Runtime/Service/UI。不能据此声称用户已经可以在产品新建Bot。B必须组合固定草稿依赖、提供可信确认/新epoch/原intent查询入口，再做同候选设备验收；不得直接双写旧AgentCatalog。

本批所有副作用仅原创合成临时BusinessStore。未读写真实用户数据库、未调用真实模型/搜索、未创建账户/配置凭据/扩权限/部署/合入。历史两次unknown、¥0.002620预占、I04拒绝和整体产品HOLD均保持原状。

最终检查说明：新增生产模块、测试、复现脚本和本报告的限定 `git diff --check` 通过，限定rustfmt检查通过。对包含原始Cargo输出的完整补丁运行 `git diff --check` 会因stdout中的测试进度尾随空格及末尾空行返回非0；这些是原始日志字节，已保留并按SHA256封存，没有修剪日志或声称完整补丁空白检查通过。测试8/8及独审结果不因此改写。
